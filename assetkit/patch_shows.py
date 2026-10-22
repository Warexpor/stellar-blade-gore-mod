#!/usr/bin/env python3
"""Patch Stellar Blade show / table JSON (UAssetAPI SerializeJson) so Eve ragdolls on death.

Usage: patch_shows.py <spec.json> <json_in_dir> <json_out_dir> [meshinfo.log]
With meshinfo.log (sbtool meshinfo), "cpuaccess" jobs are left to sbtool cpuaccess and only their imports are read.

The spec lists, per asset (relative path under SB/Content, no extension):
  "flip":   set bIgnorePlayer=false on every SBShowRagdollKey export (key already exists)
  "inject": clone the donor ragdoll key into the show with per-show overrides
  "clone":  copy another show ("from") to this new package path, then retune its ragdoll key
  "animshow": copy an animated death show ("from") to this new package path playing another animation ("anim",
            "length" s, "rm" its root motion data or null), without a ragdoll key: a death animation main.lua
            plays over her death show
  "table":  set fields on DataTable rows
  "collision": make component templates ignore collision channels (raw unversioned data)
  "physics": rework a physics asset's ragdoll: collision between body groups (CollisionDisableTable, raw
             data after the tagged properties) and per-body damping
  "cpuaccess": keep a skeletal mesh's LOD0 vertex data on the CPU (bAllowCPUAccess), which the game's
               runtime mesh slicer needs; sliceable monsters ship with it, Eve's outfits don't
  "vendor": ship a third-party asset as is ("file": legacy package under the repo, dumped by build.sh into
            $SB_VENDOR_JSON)
  "voice":  add a voice to a CharacterSoundSet's VoiceSounds map, as a copy of the entry "like" with "set"
            fields changed ("sound": the SoundSource cue's package path)
  "notify": add an SBAnimNotify_CharSESound playing voice "voice" to an AnimSequence at time "at", keeping
            every notify it has
"""
import base64, copy, json, math, os, struct, sys

RAGDOLL_CHANNEL = 23  # KeyContanerMap key used by every vanilla SBShowRagdollKey
PRELOAD_AT = 1.0e9    # a preload key's StartTime: never reached

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


def preload(d, rels):
    """Shows (SB/Content-relative) nothing else refers to, loaded with this package so Lua finds them (UE4SS's
    LoadAsset found none of the packages this mod adds). A bare import isn't enough: the IoStore conversion drops
    imports no export refers to, and the falls never loaded. Each gets a play-show key of its own pointing at it (a
    hard reference). Keys in no channel loaded them, but nothing referred to the keys: the next garbage collection
    took them and the falls with them (her death a minute after the show loaded found none). So they sit in the
    play-show channel, kept as long as the show is, disabled (bEnable false) and timed past any show's end."""
    src_idx = (exports_of(d, "SBShowPlayShowKey") or [None])[0]
    if not src_idx:
        die("preload needs a show with an SBShowPlayShowKey to copy")
    src = d["Exports"][src_idx - 1]
    main_idx, main = main_export(d)
    channel = next((k["Value"] for k, v in key_map(main)["Value"]
                    if any(x["Value"] == src_idx for x in v["Value"][0]["Value"] or [])), None)
    if channel is None:
        die("preload: the show's play-show key is in no channel")
    taken = {e["ObjectName"] for e in d["Exports"]}
    k = 1
    for rel in rels:
        name = rel.rsplit("/", 1)[1]
        pkg = ensure_import(d, "/Game/" + rel, 0, "/Script/CoreUObject", "Package")
        show = ensure_import(d, name, pkg, "/Script/SB", "SBShowData")
        while f"SBShowPlayShowKey_{k}" in taken:
            k += 1
        key = f"SBShowPlayShowKey_{k}"
        taken.add(key)
        add_name(d, key)
        new = copy.deepcopy(src)
        new.update({"ObjectName": key, "OuterIndex": main_idx,
                    "SerializationBeforeSerializationDependencies": [], "CreateBeforeSerializationDependencies": [show],
                    "SerializationBeforeCreateDependencies": [src["ClassIndex"], src["TemplateIndex"]],
                    "CreateBeforeCreateDependencies": [main_idx]})
        for p in new["Data"]:
            if p["Name"] == "ShowData":
                p["Value"] = show
        # USBShowKey's fields come before the play-show key's own (schema order)
        new["Data"] = [make_prop("StartTime", PRELOAD_AT), make_prop("bEnable", False)] + \
            [p for p in new["Data"] if p["Name"] not in ("StartTime", "bEnable")]
        d["Exports"].append(new)
        main["CreateBeforeSerializationDependencies"].append(len(d["Exports"]))
        add_key_to_channel(d, main, len(d["Exports"]), channel)


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


def anim_show(d, job):
    """The show's one SBShowAnimKey plays job["anim"] for job["length"] s and holds its last frame; the show ends
    job["hold"] s later (0.9 by default); the knockdown IK key keeps its share of the animation. Ending 0.9 s after
    the fall handed her to the game's own dead pose (her death show's, not this fall's): she snapped into it."""
    anim, length, rm = job["anim"], float(job["length"]), job.get("rm")
    name = anim.rsplit("/", 1)[1]
    keys = [e for i, e in enumerate(d["Exports"], 1) if e["ClassIndex"] < 0 and imp_name(d, e["ClassIndex"]) == "SBShowAnimKey"]
    if len(keys) != 1:
        die(f"animshow: {len(keys)} anim keys in {job['from']}")
    if exports_of(d, "SBShowRagdollKey"):
        die(f"animshow: {job['from']} already has a ragdoll key")
    old_len = None
    for p in keys[0]["Data"]:
        if p["Name"] == "AnimResourcePath":
            p["Value"] = f"AnimSequence'{anim}.{name}'"
        elif p["Name"] == "RootMotionDataPath":
            p["Value"] = rm
        elif p["Name"] in ("PlayEndTime", "Duration"):
            old_len = old_len or float(p["Value"])
            p["Value"] = length
        elif p["Name"] == "bHoldEndTime":
            p["Value"] = True
    if rm is None:
        # no root motion data for this animation: the key goes without (the property's default)
        keys[0]["Data"] = [p for p in keys[0]["Data"] if p["Name"] not in ("RootMotionKey", "RootMotionDataPath")]
    k = length / (old_len or length)
    for i in exports_of(d, "SBShowAnimBPSetValueKey"):
        for p in d["Exports"][i - 1]["Data"]:
            if p["Name"] in ("StartTime", "Duration"):
                p["Value"] = float(p["Value"]) * k
    main = next(e for e in d["Exports"] if e["OuterIndex"] == 0)
    for p in main["Data"]:
        if p["Name"] == "EndTime":
            p["Value"] = length + float(job.get("hold", 0.9))


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
    # the accessories (hair, cape, breast and hip jiggle, neck pieces) touch nothing of hers, only the world: the hip
    # and breast bodies sit inside her torso and shoved the thighs and arms every frame, and the cape and hair got
    # pinned between her and the floor, so she shook on the ground (pelvis turning 150-300 deg/s while still)
    if not job.get("accessory_collision", False):
        main = {b for g in groups for b in g}
        for a in (i for i, b in enumerate(bones) if b not in main):
            for b in range(len(bones)):
                if b != a:
                    table.add((min(a, b), max(a, b)))
    # self_collision false: none of her bodies touch each other, only the world. The runtime switch (main.lua: the
    # mesh ignores PhysicsBody) didn't stop it: an arm landing on her body still set every joint shaking
    if not job.get("self_collision", True):
        for a in range(len(bones)):
            for b in range(a + 1, len(bones)):
                table.add((a, b))
    for a, b in job.get("except", []):
        if a in idx and b in idx:
            table.add((min(idx[a], idx[b]), max(idx[a], idx[b])))
    return table


def _prop(kind, name, value, **extra):
    return {"$type": f"UAssetAPI.PropertyTypes.{kind}, UAssetAPI", **({"StructType": extra.pop("struct")} if "struct" in extra else {}),
            **({"SerializeNone": True, "StructGUID": "{00000000-0000-0000-0000-000000000000}", "SerializationControl": "NoExtension",
                "Operation": "None"} if kind == "Structs.StructPropertyData" else {}),
            "Name": name, "ArrayIndex": 0, "PropertyGuid": None, "IsZero": False, "PropertyTagFlags": "None",
            "PropertyTypeName": None, "PropertyTagExtensions": "NoExtension", **extra, "Value": value}


def _vector(name, v):
    vec = _prop("Structs.VectorPropertyData", name, {"$type": "UAssetAPI.UnrealTypes.FVector, UAssetAPI",
                                                     "X": float(v[0]), "Y": float(v[1]), "Z": float(v[2])})
    return _prop("Structs.StructPropertyData", name, [vec], struct="Vector")


def _motion(name, enum, value):
    return _prop("Objects.EnumPropertyData", name, value, EnumType=enum, InnerType="ByteProperty")


def joint_names(d):
    """Child bone of every constraint (ConstraintBone1), in ConstraintSetup order."""
    _, m = main_export(d)
    out = []
    for ref in next(p for p in m["Data"] if p["Name"] == "ConstraintSetup")["Value"]:
        inst = next(p for p in d["Exports"][ref["Value"] - 1]["Data"] if p["Name"] == "DefaultInstance")["Value"]
        out.append(next(p["Value"] for p in inst if p["Name"] == "ConstraintBone1"))
    return out


def add_joints(d, joints):
    """A locked PhysicsConstraintTemplate per joint ({child, parent, pos, pri, sec}: frame 2 in the parent body's
    space; frame 1 stays the child bone), no collision between the two, appended to ConstraintSetup."""
    if not joints:
        return
    main_idx, m = main_export(d)
    setup = next(p for p in m["Data"] if p["Name"] == "ConstraintSetup")
    have = joint_names(d)
    first = d["Exports"][setup["Value"][0]["Value"] - 1]
    used = {e["ObjectName"] for e in d["Exports"]}
    serial = max(int(n.rsplit("_", 1)[1]) for n in used if n.startswith("PhysicsConstraintTemplate_"))
    for s in ("JointName", "ConstraintBone1", "ConstraintBone2", "Pos2", "PriAxis2", "SecAxis2", "ProfileInstance",
              "ConeLimit", "TwistLimit", "Swing1Motion", "Swing2Motion", "TwistMotion", "bDisableCollision",
              "EAngularConstraintMotion", "ACM_Locked", "ConstraintInstance", "ConstraintProfileProperties",
              "ConeConstraint", "TwistConstraint", "Vector", "DefaultInstance", "PhysicsConstraintTemplate"):
        add_name(d, s)
    for j in joints:
        if j["child"] in have:
            die(f"physics: {j['child']} already has a joint")
        for s in (j["child"], j["parent"]):
            add_name(d, s)
        serial += 1
        e = copy.deepcopy(first)
        e.update({"ObjectName": f"PhysicsConstraintTemplate_{serial}", "OuterIndex": main_idx, "Extras": "",
                  "SerializationBeforeSerializationDependencies": [], "CreateBeforeSerializationDependencies": [],
                  "SerializationBeforeCreateDependencies": [first["ClassIndex"], first["TemplateIndex"]],
                  "CreateBeforeCreateDependencies": [main_idx]})
        profile = [
            _prop("Structs.StructPropertyData", "ConeLimit", [
                _motion("Swing1Motion", "EAngularConstraintMotion", "ACM_Locked"),
                _motion("Swing2Motion", "EAngularConstraintMotion", "ACM_Locked")], struct="ConeConstraint"),
            _prop("Structs.StructPropertyData", "TwistLimit", [
                _motion("TwistMotion", "EAngularConstraintMotion", "ACM_Locked")], struct="TwistConstraint"),
            _prop("Objects.BoolPropertyData", "bDisableCollision", True),
        ]
        e["Data"] = [_prop("Structs.StructPropertyData", "DefaultInstance", [
            _prop("Objects.NamePropertyData", "JointName", j["child"]),
            _prop("Objects.NamePropertyData", "ConstraintBone1", j["child"]),
            _prop("Objects.NamePropertyData", "ConstraintBone2", j["parent"]),
            _vector("Pos2", j["pos"]), _vector("PriAxis2", j["pri"]), _vector("SecAxis2", j["sec"]),
            _prop("Structs.StructPropertyData", "ProfileInstance", profile, struct="ConstraintProfileProperties"),
        ], struct="ConstraintInstance")]
        d["Exports"].append(e)
        idx = len(d["Exports"])
        ref = copy.deepcopy(setup["Value"][-1])
        ref.update({"Name": str(len(setup["Value"])), "Value": idx})
        setup["Value"].append(ref)
        # outside retoc's export chain (its last link waits for the asset itself, so chaining on would loop):
        # created after the asset, before the asset serializes the reference to it
        m["CreateBeforeSerializationDependencies"].append(idx)
        have.append(j["child"])


def _float_prop(name, v):
    return _prop("Objects.FloatPropertyData", name, float(v))


def _struct_field(d, parent, name, make):
    """The field `name` of a struct property's Value list, added (as make()) when it was left at its default."""
    p = next((q for q in parent["Value"] if q["Name"] == name), None)
    if p is None:
        add_name(d, name)
        p = make()
        parent["Value"].append(p)
    return p


def zero_limited(cone, twist, twisted, below=0.0):
    """(struct, motion prop, degrees prop) of each motion ACM_Limited to 0 deg (or under `below`); the twist only when
    no range replaces it (twisted). A motion with no degrees set is at the engine's default, 45."""
    out = []
    pairs = [(cone, "Swing1Motion", "Swing1LimitDegrees"), (cone, "Swing2Motion", "Swing2LimitDegrees")]
    if not twisted:
        pairs.append((twist, "TwistMotion", "TwistLimitDegrees"))
    for lim, m, dg in pairs:
        mp = next((q for q in lim["Value"] if q["Name"] == m), None)
        dp = next((q for q in lim["Value"] if q["Name"] == dg), None)
        if mp and dp and str(mp["Value"]).endswith("ACM_Limited") and (float(dp["Value"]) == 0.0 or float(dp["Value"]) < below):
            out.append((lim, mp, dp))
    return out


def joint_limits(d, job):
    """The main joints' limits: hard (bSoftConstraint off), the twist ("limits" from outfits.py: half range,
    frame 2 turned about the twist axis to centre it) and cone overrides ("swing")."""
    want = {b for g in job["groups"].values() for b in g}
    limits, swing, hard = job.get("limits", {}), job.get("swing", {}), job.get("hard_limits", False)
    _, m = main_export(d)
    done = []
    for ref in next((p for p in m["Data"] if p["Name"] == "ConstraintSetup"), {"Value": []})["Value"]:
        e = d["Exports"][ref["Value"] - 1]
        di = next(p for p in e["Data"] if p["Name"] == "DefaultInstance")
        child = next(p["Value"] for p in di["Value"] if p["Name"] == "ConstraintBone1")
        if child not in want:
            continue
        prof = next((p for p in di["Value"] if p["Name"] == "ProfileInstance"), None)
        if prof is None:
            die(f"physics: {child}'s joint has no ProfileInstance")
        cone = next((p for p in prof["Value"] if p["Name"] == "ConeLimit"), None)
        twist = next((p for p in prof["Value"] if p["Name"] == "TwistLimit"), None)
        if cone is None or twist is None:
            die(f"physics: {child}'s joint has no ConeLimit / TwistLimit")
        if hard:
            for lim in (cone, twist):
                _struct_field(d, lim, "bSoftConstraint", lambda: _prop("Objects.BoolPropertyData", "bSoftConstraint", False))["Value"] = False
        # a motion "limited" to 0 deg (CH_P_EVE_09's pelvis to spine cone) is locked instead: a hard limit with no
        # range shook the joint every frame. So did ranges of a few degrees (clavicles, the shoulder's roll, the hip's
        # sideways swing, the neck: 5 deg): at their limit all the time, every joint buzzed even in mid-air
        # (eighteenth playtest), so motions under lock_below degrees are locked too
        for lim, mk, dk in zero_limited(cone, twist, child in limits, job.get("lock_below", 0.0) if hard else 0.0):
            mk["Value"] = "ACM_Locked"
        # joints locked whole (locked_joints): the clavicles, whose few degrees of play shook in mid-air
        if child in job.get("locked_joints", []):
            for lim, k in ((cone, "Swing1Motion"), (cone, "Swing2Motion"), (twist, "TwistMotion")):
                _struct_field(d, lim, k, lambda: _motion(k, "EAngularConstraintMotion", "ACM_Locked"))["Value"] = "ACM_Locked"
        for k, v in swing.get(child, {}).items():
            _struct_field(d, cone, k, lambda: _float_prop(k, v))["Value"] = float(v)
        lim = limits.get(child)
        if lim:
            _struct_field(d, twist, "TwistLimitDegrees", lambda: _float_prop("TwistLimitDegrees", 0))["Value"] = float(lim["twist"])
            # frame 2 turned by "turn" about its X: the twist then reads "turn" less, so the range moves by it
            vecs = {p["Name"]: p for p in di["Value"] if p["Name"] in ("PriAxis2", "SecAxis2")}
            if len(vecs) != 2:
                die(f"physics: {child}'s joint has no PriAxis2 / SecAxis2")
            v = lambda p: p["Value"][0]["Value"]
            pri, sec = v(vecs["PriAxis2"]), v(vecs["SecAxis2"])
            a = [pri["X"], pri["Y"], pri["Z"]]
            b = [sec["X"], sec["Y"], sec["Z"]]
            c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
            t = math.radians(lim["turn"])
            n = [b[i] * math.cos(t) + c[i] * math.sin(t) for i in range(3)]
            sec.update({"X": n[0], "Y": n[1], "Z": n[2]})
        done.append(child)
    missing = set(limits) - set(done)
    if missing:
        die(f"physics: no joint for {sorted(missing)}")


def physics(d, job):
    add_joints(d, job.get("joints", []))
    joint_limits(d, job)
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
            p = next((p for p in inst if p["Name"] == k), None)
            if p is None:
                # left at its default (unserialized): a float like the body's other ones
                tmpl = next((q for q in inst if q["$type"].startswith("UAssetAPI.PropertyTypes.Objects.FloatPropertyData")), None)
                if tmpl is None or not isinstance(v, float):
                    die(f"physics: {bone} has no {k}")
                p = copy.deepcopy(tmpl)
                p["Name"] = k
                add_name(d, k)
                inst.append(p)
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
        if not names or not os.path.exists(out_path(dst, rel)):
            continue  # nothing imports from it, or not patched through JSON (cpuaccess meshes)
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


def mesh_imports(path):
    """rel -> import names, from sbtool meshinfo's "imp <rel> <package> <path>" lines."""
    out = {}
    for line in open(path):
        f = line.split()
        if len(f) == 4 and f[0] == "imp":
            out.setdefault(f[1], {}).setdefault(f[2], set()).add(f[3])
    return out


def _name_prop(name, value):
    return _prop("Objects.NamePropertyData", name, value)


def voice_pairs(d):
    """The VoiceSounds map of a CharacterSoundSet: its list of [key, value] pairs."""
    _, main = main_export(d)
    for p in main["Data"]:
        if p["Name"] == "VoiceSounds" and isinstance(p.get("Value"), list):
            return p["Value"]
    die("no VoiceSounds map")


def add_voice(d, key, job):
    pairs = voice_pairs(d)
    if any(k["Value"].lower() == key.lower() for k, _ in pairs):
        die(f"voice {key} already exists")
    src = next((pr for pr in pairs if pr[0]["Value"] == job["like"]), None) or die(f"no voice {job['like']}")
    new = copy.deepcopy(src)
    new[0]["Value"] = key
    add_name(d, key)
    fields = {q["Name"]: q for q in new[1]["Value"]}
    if "sound" in job:
        pkg_path = job["sound"]
        obj = pkg_path.rsplit("/", 1)[1]
        pkg = ensure_import(d, pkg_path, 0, "/Script/CoreUObject", "Package")
        fields["SoundSource"]["Value"] = ensure_import(d, obj, pkg, "/Script/Engine", "SoundCue")
        fields["SoundSource"]["IsZero"] = False
    for k, v in job.get("set", {}).items():
        q = fields.get(k) or die(f"voice field {k} not in {job['like']}")
        q["Value"] = type(q["Value"])(v)
        q["IsZero"] = not v
    pairs.append(new)


def notify_events(main):
    for p in main["Data"]:
        if p["Name"] == "Notifies":
            return p
    die("no Notifies")


def add_notify(d, voice, at):
    main_idx, main = main_export(d)
    sb_pkg = ensure_import(d, "/Script/SB", 0, "/Script/CoreUObject", "Package")
    cls = ensure_import(d, "SBAnimNotify_CharSESound", sb_pkg, "/Script/CoreUObject", "Class")
    tmpl = ensure_import(d, "Default__SBAnimNotify_CharSESound", sb_pkg, "/Script/SB", "SBAnimNotify_CharSESound")
    name = "SBAnimNotify_CharSESound_StellarBladeGore"
    for s_ in (name, "VoiceKey", voice, "SBCharSESound"):
        add_name(d, s_)
    events = notify_events(main)
    # a template for both: an existing notify object of this sequence and its event
    ev0 = min(events["Value"], key=lambda ev: next(q["Value"] for q in ev["Value"] if q["Name"] == "LinkValue"))
    src_idx = next(q["Value"] for q in ev0["Value"] if q["Name"] == "Notify")
    new = copy.deepcopy(d["Exports"][src_idx - 1])
    new.update({"ObjectName": name, "OuterIndex": main_idx, "ClassIndex": cls, "TemplateIndex": tmpl,
                "Data": [_name_prop("VoiceKey", voice)],
                "SerializationBeforeSerializationDependencies": [], "CreateBeforeSerializationDependencies": [],
                "SerializationBeforeCreateDependencies": [cls, tmpl], "CreateBeforeCreateDependencies": [main_idx]})
    d["Exports"].append(new)
    idx = len(d["Exports"])
    main["CreateBeforeSerializationDependencies"].append(idx)
    ev = copy.deepcopy(ev0)
    for q in ev["Value"]:
        if q["Name"] == "Notify":
            q["Value"] = idx
        elif q["Name"] == "NotifyName":
            q["Value"] = "SBCharSESound"
        elif q["Name"] == "LinkValue":
            q["Value"] = float(at)
    t = lambda e: next(q["Value"] for q in e["Value"] if q["Name"] == "LinkValue")
    events["Value"].append(ev)
    events["Value"].sort(key=t)
    for i, e in enumerate(events["Value"]):
        e["Name"] = str(i) if e.get("Name", "").isdigit() else e.get("Name")


def main():
    spec_path, src, dst = sys.argv[1:4]
    spec = json.load(open(spec_path))
    load = lambda rel: json.load(open(os.path.join(src, rel + ".json")))
    donor = load(spec["donor"])
    # cpuaccess meshes are patched by sbtool, without JSON; their imports still count for fix_public
    imports = mesh_imports(sys.argv[4]) if len(sys.argv) > 4 else {}
    outputs = {}
    # one package at a time: with every outfit mesh in the spec, holding them all would take gigabytes
    for rel, job in spec["assets"].items():
        mode = job["mode"]
        if mode == "cpuaccess" and len(sys.argv) > 4:
            outputs[rel] = imports.get(rel, {})
            continue
        if mode == "vendor":
            d = json.load(open(os.path.join(os.environ["SB_VENDOR_JSON"], rel + ".json")))
        else:
            d = load(job["from"] if mode in ("clone", "animshow") else rel)
        if mode == "animshow":
            rename_package(d, job["from"], rel)
            anim_show(d, job)
        elif mode == "clone":
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
        elif mode == "vendor":
            pass
        elif mode == "voice":
            for key, v in job["voices"].items():
                add_voice(d, key, v)
        elif mode == "notify":
            add_notify(d, job["voice"], job["at"])
        elif mode == "collision":
            for comp, chans in job["ignore"].items():
                ignore_channels(d, comp, chans)
        else:
            die(f"bad mode {mode}")
        if job.get("preload"):
            preload(d, job["preload"])
        outputs[rel] = full_import_names(d)
        os.makedirs(os.path.dirname(out_path(dst, rel)), exist_ok=True)
        json.dump(d, open(out_path(dst, rel), "w"), indent=1)
        print(f"{mode:6s} {rel}")
    fix_public(dst, outputs)


if __name__ == "__main__":
    main()
