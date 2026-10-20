#!/usr/bin/env python3
"""Patch Stellar Blade show / table JSON (UAssetAPI SerializeJson) so Eve ragdolls on death.

Usage: patch_shows.py <spec.json> <json_in_dir> <json_out_dir>

The spec lists, per asset (relative path under SB/Content, no extension):
  "flip":   set bIgnorePlayer=false on every SBShowRagdollKey export (key already exists)
  "inject": clone the donor ragdoll key into the show with per-show overrides
  "clone":  copy another show ("from") to this new package path, then retune its ragdoll key
  "table":  set fields on DataTable rows
  "collision": make component templates ignore collision channels (raw unversioned data)
  "physics": rework a physics asset's ragdoll: collision between body groups (CollisionDisableTable, raw
             data after the tagged properties) and per-body damping
  "cpuaccess": keep a skeletal mesh's LOD0 vertex data on the CPU (bAllowCPUAccess), which the game's
               runtime mesh slicer needs; sliceable monsters ship with it, Eve's outfits don't
"""
import base64, copy, json, os, struct, sys

RAGDOLL_CHANNEL = 23  # KeyContanerMap key used by every vanilla SBShowRagdollKey

# Schema order (USBShowKey then USBShowRagdollKey), matches the exe reflection data.
ORDER = [
    "CheckShowKeyTag", "CheckNoneShowKeyTag", "IsBattle", "StartTime", "bKeepPlaying", "bCheckHitLevel",
    "bEnable", "bNeedsExecutionKey", "Duration",
    "BoneName", "LockBodyLocationType", "bStopWhenZeroVelocity", "FadeInTime", "FadeOutTime", "bDisableGravity",
    "bUseMassScale", "bEnablePhysicsBodyCollision", "CapsuleComponentFollowingSocketName", "MassScaleCurve",
    "PoseSnapshotDelayTime", "bUseImpulse", "ImpulseDelayTime", "bOverrideHitBone", "ImpulseBoneName",
    "ImpulsePower", "DirectionType", "AdditiveDirectionPercent", "bCheckAdditiveDirectionNearlyParallel",
    "AdditiveDirectionType", "bAdditiveDirectionWhenNotStatic", "ImpulseDirection", "ImpulseLimitVelocity",
    "bUseForce", "ForceBoneArray", "Force", "ForceScaleCurve", "Target", "PlayTargetIndex", "bIgnorePlayer",
]
TYPES = {
    "Bool": "UAssetAPI.PropertyTypes.Objects.BoolPropertyData, UAssetAPI",
    "Float": "UAssetAPI.PropertyTypes.Objects.FloatPropertyData, UAssetAPI",
    "Byte": "UAssetAPI.PropertyTypes.Objects.BytePropertyData, UAssetAPI",
    "Name": "UAssetAPI.PropertyTypes.Objects.NamePropertyData, UAssetAPI",
    "Int": "UAssetAPI.PropertyTypes.Objects.IntPropertyData, UAssetAPI",
}
KIND = {n: "Bool" for n in ORDER if n.startswith("b")}
KIND.update({n: "Float" for n in ("StartTime", "Duration", "FadeInTime", "FadeOutTime", "PoseSnapshotDelayTime",
                                  "ImpulseDelayTime", "ImpulsePower", "AdditiveDirectionPercent", "ImpulseLimitVelocity")})
KIND.update({n: "Byte" for n in ("IsBattle", "LockBodyLocationType", "DirectionType", "AdditiveDirectionType", "Target")})
KIND.update({n: "Name" for n in ("BoneName", "CapsuleComponentFollowingSocketName", "ImpulseBoneName")})
KIND["PlayTargetIndex"] = "Int"


def die(msg):
    sys.exit("patch_shows: " + msg)


def imp_name(d, idx):
    return d["Imports"][-idx - 1]["ObjectName"]


def exports_of(d, cls):
    return [i for i, e in enumerate(d["Exports"], 1) if e["ClassIndex"] < 0 and imp_name(d, e["ClassIndex"]) == cls]


def add_name(d, s):
    if s is not None and s not in d["NameMap"]:
        d["NameMap"].append(s)


def ensure_import(d, obj, outer, cls_pkg, cls_name):
    for i, im in enumerate(d["Imports"]):
        if im["ObjectName"] == obj and im["ClassName"] == cls_name:
            return -(i + 1)
    d["Imports"].append({"$type": "UAssetAPI.Import, UAssetAPI", "ObjectName": obj, "OuterIndex": outer,
                         "ClassPackage": cls_pkg, "ClassName": cls_name, "PackageName": None, "bImportOptional": False})
    for s in (obj, cls_pkg, cls_name):
        add_name(d, s)
    return -len(d["Imports"])


def make_prop(name, value):
    kind = KIND.get(name) or die(f"no type for {name}")
    p = {"$type": TYPES[kind], "Name": name, "ArrayIndex": 0, "PropertyGuid": None, "IsZero": False,
         "PropertyTagFlags": "None", "PropertyTypeName": None, "PropertyTagExtensions": "NoExtension"}
    if kind == "Byte":
        p.update({"ByteType": "Byte", "EnumType": None, "Value": int(value)})
        p["IsZero"] = int(value) == 0
    elif kind == "Float":
        p["Value"] = float(value)
        p["IsZero"] = float(value) == 0.0
    elif kind == "Bool":
        p["Value"] = bool(value)
        p["IsZero"] = not value
    elif kind == "Int":
        p["Value"] = int(value)
        p["IsZero"] = int(value) == 0
    else:
        p["Value"] = value
        p["IsZero"] = value is None
    return p


def set_props(d, export, overrides):
    data = export["Data"]
    by = {p["Name"]: p for p in data}
    for k, v in overrides.items():
        if k not in ORDER:
            die(f"unknown ragdoll field {k}")
        if KIND.get(k) == "Name":
            add_name(d, v)
        if k in by and KIND.get(k) not in ("Byte",):
            new = make_prop(k, v)
            by[k].update({"Value": new["Value"], "IsZero": new["IsZero"]})
        else:
            by[k] = make_prop(k, v)
    export["Data"] = sorted(by.values(), key=lambda p: ORDER.index(p["Name"]))


def main_export(d):
    for i, e in enumerate(d["Exports"], 1):
        if e["OuterIndex"] == 0:
            return i, e
    die("no main export")


def key_map(e):
    for p in e["Data"]:
        if p["Name"] == "KeyContanerMap":
            return p
    die("show has no KeyContanerMap")


def add_key_to_channel(d, main, export_idx, channel):
    m = key_map(main)
    for k, v in m["Value"]:
        if k["Value"] == channel:
            arr = v["Value"][0]
            arr["Value"] = arr["Value"] or []
            arr["Value"].append({"$type": "UAssetAPI.PropertyTypes.Objects.ObjectPropertyData, UAssetAPI",
                                 "Name": str(len(arr["Value"])), "ArrayIndex": 0, "PropertyGuid": None,
                                 "IsZero": False, "PropertyTagFlags": "None", "PropertyTypeName": None,
                                 "PropertyTagExtensions": "NoExtension", "Value": export_idx})
            return
    tmpl = copy.deepcopy(m["Value"][0])
    tmpl[0]["Value"] = channel
    tmpl[1]["Value"][0]["Value"] = []
    m["Value"].append(tmpl)
    add_key_to_channel(d, main, export_idx, channel)


def inject(d, donor, overrides):
    if exports_of(d, "SBShowRagdollKey"):
        die("show already has a ragdoll key; use flip")
    src_idx = exports_of(donor, "SBShowRagdollKey")[0]
    src = donor["Exports"][src_idx - 1]
    for s in ("SBShowRagdollKey_0", "SBShowKeyContainer", "RuntimeFloatCurve", "RichCurve", "RichCurveKey", "Vector"):
        add_name(d, s)
    sb_pkg = next(-(i + 1) for i, im in enumerate(d["Imports"]) if im["ObjectName"] == "/Script/SB")
    cls = ensure_import(d, "SBShowRagdollKey", sb_pkg, "/Script/CoreUObject", "Class")
    tmpl = ensure_import(d, "Default__SBShowRagdollKey", sb_pkg, "/Script/SB", "SBShowRagdollKey")
    main_idx, main = main_export(d)
    new = copy.deepcopy(src)
    new.update({"ObjectName": "SBShowRagdollKey_0", "OuterIndex": main_idx, "ClassIndex": cls, "TemplateIndex": tmpl,
                "SerializationBeforeSerializationDependencies": [], "CreateBeforeSerializationDependencies": [],
                "SerializationBeforeCreateDependencies": [cls, tmpl], "CreateBeforeCreateDependencies": [main_idx]})
    d["Exports"].append(new)
    idx = len(d["Exports"])
    main["CreateBeforeSerializationDependencies"].append(idx)
    for p in new["Data"]:
        if p["Name"].endswith("BoneName"):
            add_name(d, p["Value"])
    set_props(d, new, overrides)
    add_key_to_channel(d, main, idx, RAGDOLL_CHANNEL)


def flip(d, overrides):
    idxs = exports_of(d, "SBShowRagdollKey")
    if not idxs:
        die("flip target has no ragdoll key")
    for i in idxs:
        set_props(d, d["Exports"][i - 1], overrides)


def rename_package(d, src_rel, dst_rel):
    old_path, new_path = "/Game/" + src_rel, "/Game/" + dst_rel
    old_name, new_name = old_path.rsplit("/", 1)[1], new_path.rsplit("/", 1)[1]
    if new_path in d["NameMap"] or new_name in d["NameMap"]:
        die(f"clone target name already present: {dst_rel}")
    d["NameMap"] = [new_path if n == old_path else new_name if n == old_name else n for n in d["NameMap"]]
    d["FolderName"] = new_path
    for e in d["Exports"]:
        if e["ObjectName"] == old_name:
            e["ObjectName"] = new_name


def retarget(d, mapping):
    """Point imported assets elsewhere: {"/Game/Old/Path": "/Game/New/Path"} (package + object import)."""
    for old_path, new_path in mapping.items():
        old_name, new_name = old_path.rsplit("/", 1)[1], new_path.rsplit("/", 1)[1]
        for i, im in enumerate(d["Imports"]):
            if im["ObjectName"] == old_path and im["ClassName"] == "Package":
                im["ObjectName"] = new_path
                add_name(d, new_path)
                for o in d["Imports"]:
                    if o["OuterIndex"] == -(i + 1) and o["ObjectName"] == old_name:
                        o["ObjectName"] = new_name
                        add_name(d, new_name)


def table(d, rows):
    e = d["Exports"][0]
    for row in e["Table"]["Data"]:
        if row["Name"] in rows:
            for p in row["Value"]:
                if p["Name"] in rows[row["Name"]]:
                    v = rows[row["Name"]][p["Name"]]
                    p["Value"] = v
                    p["IsZero"] = v in ("", None) or (isinstance(v, (int, float)) and not isinstance(v, bool) and v == 0)


def response_array(b, names):
    """Locate the single TArray<FResponseChannel> in a component's raw unversioned data.

    Each element is one unversioned struct: header 0x0580 + zero mask 0x02 + FName (Response=Ignore, zeroed),
    or header 0x0500 + FName + response byte. Returns (count_offset, elements) with (offset, channel, response).
    """
    def walk(at, n):
        out = []
        for _ in range(n):
            h = struct.unpack_from("<H", b, at)[0] if at + 11 <= len(b) else None
            if h == 0x0580 and b[at + 2] == 0x02:
                idx, num, resp = *struct.unpack_from("<ii", b, at + 3), 0
            elif h == 0x0500 and b[at + 10] in (1, 2):
                idx, num, resp = *struct.unpack_from("<ii", b, at + 2), b[at + 10]
            else:
                return None
            if not (0 <= idx < len(names)) or num != 0:
                return None
            out.append((at, names[idx], resp))
            at += 11
        return out
    hits = []
    for at in range(len(b) - 4):
        n = struct.unpack_from("<i", b, at)[0]
        if 0 < n < 64:
            els = walk(at + 4, n)
            if els:
                hits.append((at, els))
    if len(hits) != 1:
        die(f"expected one response array, found {len(hits)}")
    return hits[0]


def ignore_channels(d, export_name, channels):
    e = next((x for x in d["Exports"] if x["ObjectName"] == export_name), None) or die(f"no export {export_name}")
    b = bytearray(base64.b64decode(e["Data"]))
    count_at, els = response_array(b, d["NameMap"])
    have = {ch: (at, resp) for at, ch, resp in els}
    end = els[-1][0] + 11
    for ch in channels:
        if ch not in d["NameMap"]:
            die(f"channel {ch} not in name map")
        elem = b"\x80\x05\x02" + struct.pack("<ii", d["NameMap"].index(ch), 0)
        if ch in have:
            at, _ = have[ch]
            b[at:at + 11] = elem
        else:
            b[end:end] = elem
            end += 11
            struct.pack_into("<i", b, count_at, struct.unpack_from("<i", b, count_at)[0] + 1)
    e["Data"] = base64.b64encode(bytes(b)).decode()


def cpu_access(d, lods):
    _, e = main_export(d)
    info = next((p for p in e["Data"] if p["Name"] == "LODInfo"), None) or die("no LODInfo")
    for i in lods:
        lod = info["Value"][i]["Value"]
        flag = next((p for p in lod if p["Name"] == "bAllowCPUAccess"), None) or die(f"LOD{i} has no bAllowCPUAccess")
        flag["Value"] = True


def physics_bodies(d):
    """Body index -> bone name, in SkeletalBodySetups order (the indices CollisionDisableTable uses)."""
    _, m = main_export(d)
    setups = next(p for p in m["Data"] if p["Name"] == "SkeletalBodySetups")["Value"]
    out = []
    for ref in setups:
        e = d["Exports"][ref["Value"] - 1]
        out.append((e, next(p for p in e["Data"] if p["Name"] == "BoneName")["Value"]))
    return out


def disable_table(d):
    _, m = main_export(d)
    ex = base64.b64decode(m["Extras"])
    n = struct.unpack_from("<i", ex, 0)[0]
    pairs = [struct.unpack_from("<ii", ex, 4 + 12 * i) for i in range(n)]
    return {(min(a, b), max(a, b)) for a, b in pairs}, ex[4 + 12 * n:]


def physics_table(d, job):
    """The CollisionDisableTable the job asks for: cross-group pairs collide, pairs inside a group and listed
    exceptions don't. Some outfits ship with neighbouring torso bodies colliding (CH_P_EVE_09: Pelvis/Spine/
    Spine1/Spine2, all overlapping at rest), which spins the ragdoll; every other pair keeps its vanilla setting."""
    bones = [b for _, b in physics_bodies(d)]
    idx = {b: i for i, b in enumerate(bones)}
    table, _ = disable_table(d)
    groups = list(job["groups"].values())
    for g in groups:
        present = [idx[b] for b in g if b in idx]
        for i, a in enumerate(present):
            for b in present[i + 1:]:
                table.add((min(a, b), max(a, b)))
    for gi, ga in enumerate(groups):
        for gb in groups[gi + 1:]:
            for a in ga:
                for b in gb:
                    if a not in idx or b not in idx:
                        if job.get("optional_bodies"):
                            continue  # outfits without a body on that bone
                        die(f"physics: no body for {a} / {b}")
                    table.discard((min(idx[a], idx[b]), max(idx[a], idx[b])))
    for a, b in job.get("except", []):
        if a in idx and b in idx:
            table.add((min(idx[a], idx[b]), max(idx[a], idx[b])))
    return table


def physics(d, job):
    table = physics_table(d, job)
    _, tail = disable_table(d)
    _, m = main_export(d)
    # TMap<FRigidBodyIndexPair, bool>: count, then (int32 a, int32 b, bool as uint32); presence = no collision
    body = b"".join(struct.pack("<iiI", a, b, 0) for a, b in sorted(table))
    m["Extras"] = base64.b64encode(struct.pack("<i", len(table)) + body + tail).decode()
    want = {b for g in job["groups"].values() for b in g}
    for e, bone in physics_bodies(d):
        if bone not in want:
            continue
        inst = next(p for p in e["Data"] if p["Name"] == "DefaultInstance")["Value"]
        for k, v in job.get("body", {}).items():
            p = next((p for p in inst if p["Name"] == k), None) or die(f"physics: {bone} has no {k}")
            p["Value"] = v


def full_import_names(d):
    """Package path -> object paths (lowercase, '/'-joined like retoc) that this package imports."""
    imps = d["Imports"]
    def path(i):
        im = imps[-i - 1]
        return im["ObjectName"] if im["OuterIndex"] == 0 else path(im["OuterIndex"]) + "/" + im["ObjectName"]
    out = {}
    for i in range(1, len(imps) + 1):
        if imps[i - 1]["OuterIndex"] == 0:
            continue  # the package itself
        root = -i
        while imps[-root - 1]["OuterIndex"] != 0:
            root = imps[-root - 1]["OuterIndex"]
        out.setdefault(imps[-root - 1]["ObjectName"].lower(), set()).add(path(-i).lower())
    return out


def fix_public(dst, outputs):
    """retoc's legacy output drops RF_Public on subobjects other packages import (e.g. a mesh importing its
    physics asset's body setup); repacking two such packages together then fails. Put the flag back.
    outputs: rel -> import names (full_import_names) of the patched packages already written under dst."""
    wanted = {}
    for names_by_pkg in outputs.values():
        for pkg, names in names_by_pkg.items():
            wanted.setdefault(pkg, set()).update(names)
    for rel in outputs:
        pkg = "/game/" + rel.lower()
        names = wanted.get(pkg)
        if not names:
            continue
        d = json.load(open(out_path(dst, rel)))
        def epath(i):
            e = d["Exports"][i - 1]
            return e["ObjectName"] if e["OuterIndex"] == 0 else epath(e["OuterIndex"]) + "/" + e["ObjectName"]
        changed = False
        for i, e in enumerate(d["Exports"], 1):
            if (pkg + "/" + epath(i).lower()) in names and "RF_Public" not in e["ObjectFlags"]:
                e["ObjectFlags"] = "RF_Public, " + e["ObjectFlags"]
                changed = True
        if changed:
            json.dump(d, open(out_path(dst, rel), "w"), indent=1)


def out_path(dst, rel):
    return os.path.join(dst, rel + ".json")


def main():
    spec_path, src, dst = sys.argv[1:4]
    spec = json.load(open(spec_path))
    load = lambda rel: json.load(open(os.path.join(src, rel + ".json")))
    donor = load(spec["donor"])
    outputs = {}
    # one package at a time: with every outfit mesh in the spec, holding them all would take gigabytes
    for rel, job in spec["assets"].items():
        mode = job["mode"]
        d = load(job["from"] if mode == "clone" else rel)
        if mode == "clone":
            rename_package(d, job["from"], rel)
            retarget(d, spec.get("clone_retarget", {}))
            if exports_of(d, "SBShowRagdollKey"):
                flip(d, {**spec["clone_defaults"], **job.get("set", {})})
            else:
                inject(d, donor, {**spec["inject_defaults"], **job.get("set", {})})
        elif mode == "flip":
            flip(d, {**spec["flip_defaults"], **job.get("set", {})})
        elif mode == "inject":
            inject(d, donor, {**spec["inject_defaults"], **job.get("set", {})})
        elif mode == "table":
            table(d, job["rows"])
        elif mode == "physics":
            physics(d, job)
        elif mode == "cpuaccess":
            cpu_access(d, job.get("lods", [0]))
        elif mode == "collision":
            for comp, chans in job["ignore"].items():
                ignore_channels(d, comp, chans)
        else:
            die(f"bad mode {mode}")
        outputs[rel] = full_import_names(d)
        os.makedirs(os.path.dirname(out_path(dst, rel)), exist_ok=True)
        json.dump(d, open(out_path(dst, rel), "w"), indent=1)
        print(f"{mode:6s} {rel}")
    fix_public(dst, outputs)


if __name__ == "__main__":
    main()
