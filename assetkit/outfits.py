#!/usr/bin/env python3
"""Expand the spec's "outfits" job into per-asset cpuaccess / physics jobs for every Eve outfit.

  outfits.py meshes  <spec> <EquipmentTable.json>                candidate mesh packages (SB/Content-relative)
  outfits.py physics <spec> <meshinfo.log>                       "<mesh> <physics asset>" for usable body meshes
  outfits.py expand  <spec> <json_root> <bones_root> <pairs_file> <out_spec>

Outfit meshes come from EquipmentTable (every SkeletalMesh path under Art/Character/PC/CH_P_EVE*), filtered to
meshes on Eve's body skeleton. Each physics asset gets the job's groups, and its "except" pairs are measured: two
bodies (of different groups, or not grouped at all) that are closer than rest_margin cm in the mesh's bind pose
would be shoved apart by the solver every frame (the flinging), so they stay non-colliding. Bodies no constraint
holds ("joints", see orphan_joints) get a locked joint to the body above them.
"""
import fnmatch
import json
import math
import re
import sys

PREFIX = "/Game/"


def die(msg):
    sys.exit("outfits: " + msg)


def job_of(spec):
    return spec.get("outfits") or die("spec has no outfits job")


def selected(job, rel):
    name = rel.rsplit("/", 1)[1]
    if job.get("only") and not any(fnmatch.fnmatch(name, p) for p in job["only"]):
        return False
    return not any(fnmatch.fnmatch(name, p) for p in job.get("skip", []))


def cmd_meshes(spec, table):
    job = job_of(spec)
    text = open(table).read()
    found = set()
    for m in re.finditer(r"/Game/(Art/Character/PC/CH_P_EVE[^\"'.]*)\.[A-Za-z0-9_]+", text):
        rel = m.group(1)
        if selected(job, rel):
            found.add(rel)
    for rel in sorted(found):
        print(rel)


def main_export(d):
    return next(e for e in d["Exports"] if e["OuterIndex"] == 0)


def cmd_physics(spec, meshinfo):
    """sbtool meshinfo's "ok <rel> <skeleton> <physics package>" lines -> "<mesh> <physics asset>" for body meshes."""
    job = job_of(spec)
    for line in open(meshinfo):
        f = line.split()
        if len(f) != 4 or f[0] != "ok" or f[2] != job["skeleton"] or not f[3].startswith(PREFIX):
            continue
        print(f[1], f[3][len(PREFIX):])


# --- bind-pose geometry -------------------------------------------------------------------------------------

def qmul(a, b):
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    return (w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def qrot(q, v):
    u, w = q[:3], q[3]
    return add(v, mul(cross(u, add(cross(u, v), mul(v, w))), 2))


def world_pose(bones):
    R, T = [None] * len(bones), [None] * len(bones)
    for i, b in enumerate(bones):
        q, t, p = tuple(b["rot"]), tuple(b["loc"]), b["parent"]
        R[i], T[i] = (q, t) if p < 0 else (qmul(R[p], q), add(T[p], qrot(R[p], t)))
    return R, T


def rotator_quat(pitch, yaw, roll):
    h = math.pi / 360
    sp, cp = math.sin(pitch * h), math.cos(pitch * h)
    sy, cy = math.sin(yaw * h), math.cos(yaw * h)
    sr, cr = math.sin(roll * h), math.cos(roll * h)
    return (cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy)


def seg_dist(p1, q1, p2, q2):
    d1, d2, r = sub(q1, p1), sub(q2, p2), sub(p1, p2)
    a, e, f = dot(d1, d1), dot(d2, d2), dot(d2, r)
    clamp = lambda x: min(1.0, max(0.0, x))
    if a < 1e-9 and e < 1e-9:
        s = t = 0.0
    elif a < 1e-9:
        s, t = 0.0, clamp(f / e)
    else:
        c = dot(d1, r)
        if e < 1e-9:
            s, t = clamp(-c / a), 0.0
        else:
            b = dot(d1, d2)
            den = a * e - b * b
            s = clamp((b * f - c * e) / den) if den > 1e-9 else 0.0
            t = (b * s + f) / e
            if t < 0:
                s, t = clamp(-c / a), 0.0
            elif t > 1:
                s, t = clamp((b - c) / a), 1.0
    return math.dist(add(p1, mul(d1, s)), add(p2, mul(d2, t)))


def num(v):
    return float(v) if v not in (None, "", "+0", "-0") else 0.0


def body_capsules(e, R, T):
    """Every shape of a SkeletalBodySetup as a world-space capsule (segment + radius); boxes use their long axis."""
    data = {p["Name"]: p for p in e["Data"]}
    agg = {p["Name"]: p for p in (data.get("AggGeom", {}).get("Value") or [])}
    out = []
    for kind in ("SphylElems", "SphereElems", "BoxElems", "TaperedCapsuleElems"):
        for el in agg.get(kind, {}).get("Value") or []:
            f = {p["Name"]: p for p in el["Value"]}

            def struct(n, keys):
                v = f.get(n)
                return tuple(num(v["Value"][0]["Value"][k]) for k in keys) if v and v["Value"] else (0.0,) * 3

            q = qmul(R, rotator_quat(*struct("Rotation", ("Pitch", "Yaw", "Roll"))))
            c = add(T, qrot(R, struct("Center", ("X", "Y", "Z"))))
            val = lambda n: num(f[n]["Value"]) if n in f else 0.0
            if kind == "SphereElems":
                out.append((c, c, val("Radius")))
            elif kind == "BoxElems":
                ext = [val("X") / 2, val("Y") / 2, val("Z") / 2]
                k = max(range(3), key=lambda i: ext[i])
                r = sorted(ext)[1]
                ax = qrot(q, tuple(1.0 if i == k else 0.0 for i in range(3)))
                out.append((sub(c, mul(ax, ext[k] - r)), add(c, mul(ax, ext[k] - r)), r))
            else:
                r = val("Radius") if kind == "SphylElems" else max(val("Radius0"), val("Radius1"))
                ax = qrot(q, (0.0, 0.0, 1.0))
                h = val("Length") / 2
                out.append((sub(c, mul(ax, h)), add(c, mul(ax, h)), r))
    return out


def rest_overlaps(phys, bones, groups, margin):
    names = [b["name"] for b in bones]
    R, T = world_pose(bones)
    m = main_export(phys)
    setups = next(p for p in m["Data"] if p["Name"] == "SkeletalBodySetups")["Value"]
    caps = {}
    for ref in setups:
        e = phys["Exports"][ref["Value"] - 1]
        bone = next(p for p in e["Data"] if p["Name"] == "BoneName")["Value"]
        if bone in names:
            i = names.index(bone)
            caps[bone] = body_capsules(e, R[i], T[i])
    # every body, not just the grouped ones: a jiggle, cape or accessory body that overlaps another at rest gets
    # shoved out of it every frame once both simulate (CH_P_EVE_09's hip bodies inside the pelvis)
    group_of = {b: g for g, bs in groups.items() for b in bs if b in caps}
    out = []
    bs = sorted(caps)
    for i, a in enumerate(bs):
        for b in bs[i + 1:]:
            if (a in group_of and group_of.get(b) == group_of[a]) or not caps[a] or not caps[b]:
                continue  # same group: never collides anyway
            gap = min(seg_dist(x[0], x[1], y[0], y[1]) - x[2] - y[2] for x in caps[a] for y in caps[b])
            if gap < margin:
                out.append((a, b, gap))
    return out


def orphan_joints(phys, bones, groups):
    """Bodies that no constraint ties to anything above them (twist / helper bones carrying a cape or a jiggle
    chain, e.g. CH_P_EVE_09's Ab-L-UpperArm-Tw1). In gameplay they are kinematic, so it never shows; once she
    ragdolls they fly free and drag the skin weighted to them off the arm. Each gets a locked joint to the nearest
    ancestor that has a body, framed at the bind pose (frame 1 = the child bone, frame 2 = the child relative to
    that ancestor, as PhAT makes them). The main skeleton's own bodies are left alone."""
    names = [b["name"] for b in bones]
    R, T = world_pose(bones)
    m = main_export(phys)
    bodies = []
    for ref in next(p for p in m["Data"] if p["Name"] == "SkeletalBodySetups")["Value"]:
        e = phys["Exports"][ref["Value"] - 1]
        bodies.append(next(p for p in e["Data"] if p["Name"] == "BoneName")["Value"])
    children = set()
    for ref in next((p for p in m["Data"] if p["Name"] == "ConstraintSetup"), {"Value": []})["Value"]:
        e = phys["Exports"][ref["Value"] - 1]
        inst = next(p for p in e["Data"] if p["Name"] == "DefaultInstance")["Value"]
        children.add(next(p["Value"] for p in inst if p["Name"] == "ConstraintBone1"))
    main = {b for g in groups.values() for b in g}
    out = []
    for b in bodies:
        if b in children or b in main or b not in names:
            continue
        c = names.index(b)
        a = bones[c]["parent"]
        while a >= 0 and names[a] not in bodies:
            a = bones[a]["parent"]
        if a < 0:
            continue
        ia = (-R[a][0], -R[a][1], -R[a][2], R[a][3])
        q = qmul(ia, R[c])
        out.append({"child": b, "parent": names[a], "pos": [round(x, 4) for x in qrot(ia, sub(T[c], T[a]))],
                    "pri": [round(x, 6) for x in qrot(q, (1.0, 0.0, 0.0))],
                    "sec": [round(x, 6) for x in qrot(q, (0.0, 1.0, 0.0))]})
    return out



def _inst_vec(inst, name, default):
    p = next((q for q in inst if q["Name"] == name), None)
    if p is None:
        return default
    v = p["Value"][0]["Value"] if isinstance(p["Value"], list) else p["Value"]
    return (float(v["X"]), float(v["Y"]), float(v["Z"]))


def _frame(q, pri, sec):
    """A constraint frame's axes (X = pri, Y = sec, Z = pri x sec) in world space, as rows."""
    x, y = qrot(q, pri), qrot(q, sec)
    return (x, y, cross(x, y))


def joint_limits(phys, bones, ranges):
    """The main joints' twist is their bend (knee, elbow, hip, shoulder, spine, neck: PhAT framed them as hinges
    about X), limited the same both ways round a zero of the asset's own. Vanilla knees went from 19 deg past
    straight to 121 bent, elbows from 24 past straight to 76 (with soft limits, further). Each gets the range of
    "ranges" (degrees its far end may swing towards her front / her back from the bind pose): twist = half of it,
    "turn" = how far frame 2 turns about the twist axis to centre it there. Her front is from the feet to the toes."""
    names = [b["name"] for b in bones]
    R, T = world_pose(bones)
    if "Bip001-L-Toe0" not in names:
        return {}, ["no Bip001-L-Toe0 (no front)"]
    f = sub(T[names.index("Bip001-L-Toe0")], T[names.index("Bip001-L-Foot")])
    f = (f[0], f[1], 0.0)
    fwd = mul(f, 1 / math.sqrt(dot(f, f)))
    m = main_export(phys)
    out, notes = {}, []
    for ref in next((p for p in m["Data"] if p["Name"] == "ConstraintSetup"), {"Value": []})["Value"]:
        e = phys["Exports"][ref["Value"] - 1]
        inst = next(p for p in e["Data"] if p["Name"] == "DefaultInstance")["Value"]
        child = next(p["Value"] for p in inst if p["Name"] == "ConstraintBone1")
        parent = next(p["Value"] for p in inst if p["Name"] == "ConstraintBone2")
        r = ranges.get(child)
        if not r or child not in names or parent not in names:
            continue
        c, a = names.index(child), names.index(parent)
        end = r["end"]
        if end not in names:
            notes.append(f"{child}: no {end}")
            continue
        f1 = _frame(R[c], _inst_vec(inst, "PriAxis1", (1.0, 0.0, 0.0)), _inst_vec(inst, "SecAxis1", (0.0, 1.0, 0.0)))
        f2 = _frame(R[a], _inst_vec(inst, "PriAxis2", (1.0, 0.0, 0.0)), _inst_vec(inst, "SecAxis2", (0.0, 1.0, 0.0)))
        # the child frame in the parent frame (frame 2 is the parent's, as PhysX's actor 0), its twist about X
        rel = [[dot(f2[i], f1[j]) for j in range(3)] for i in range(3)]
        w = math.sqrt(max(0.0, 1 + rel[0][0] + rel[1][1] + rel[2][2])) / 2
        x = (rel[2][1] - rel[1][2]) / (4 * w) if w > 1e-6 else 1.0
        at_bind = math.degrees(2 * math.atan2(x, w))
        limb = sub(T[names.index(end)], T[c])
        limb = mul(limb, 1 / math.sqrt(dot(limb, limb)))
        ahead = dot(cross(f1[0], limb), fwd)
        if abs(ahead) < 0.5:
            notes.append(f"{child}: its twist doesn't bend it front to back ({ahead:+.2f})")
            continue
        # a positive twist swings the far end forward when ahead > 0
        lo, hi = (-r["back"], r["front"]) if ahead > 0 else (-r["front"], r["back"])
        lo, hi = lo + at_bind, hi + at_bind
        out[child] = {"twist": round((hi - lo) / 2, 2), "turn": round((hi + lo) / 2, 2)}
        notes.append(f"{child} {at_bind:+.0f} at bind, twist {out[child]['twist']} turned {out[child]['turn']:+}")
    return out, notes

def cmd_expand(spec, root, bones_root, pairs_file, out_spec):
    job = job_of(spec)
    pairs = [l.split() for l in open(pairs_file) if l.strip()]
    assets = dict(spec["assets"])
    phys_mesh = {}
    for mesh, phys in pairs:
        if mesh not in assets:
            assets[mesh] = {"mode": "cpuaccess", "lods": job["cpuaccess_lods"]}
        phys_mesh.setdefault(phys, mesh)
    report = []
    for phys, mesh in sorted(phys_mesh.items()):
        if phys in assets:
            continue
        try:
            d = json.load(open(f"{root}/{phys}.json"))
        except FileNotFoundError:
            report.append(f"skip {phys} (not round-trippable)")
            continue
        bones = json.load(open(f"{bones_root}/SB/Content/{mesh}.json"))["bones"]
        over = rest_overlaps(d, bones, job["groups"], job["rest_margin"])
        joints = orphan_joints(d, bones, job["groups"]) if job.get("lock_orphans", True) else []
        limits, notes = joint_limits(d, bones, job.get("ranges", {}))
        report.append(f"{phys}: {len(over)} rest overlaps " + ", ".join(f"{a}/{b} {g:.1f}" for a, b, g in over)
                      + "".join(f"; locks {j['child']} to {j['parent']}" for j in joints)
                      + ("; limits " + ", ".join(notes) if notes else ""))
        assets[phys] = {"mode": "physics", "groups": job["groups"], "except": [[a, b] for a, b, _ in over],
                        "body": job["body"], "joints": joints, "limits": limits, "swing": job.get("swing", {}),
                        "hard_limits": job.get("hard_limits", True), "optional_bodies": True,
                        "accessory_collision": job.get("accessory_collision", False)}
    out = dict(spec)
    out["assets"] = assets
    json.dump(out, open(out_spec, "w"), indent=2)
    print("\n".join(report))


if __name__ == "__main__":
    cmd, spec = sys.argv[1], json.load(open(sys.argv[2]))
    if cmd == "meshes":
        cmd_meshes(spec, sys.argv[3])
    elif cmd == "physics":
        cmd_physics(spec, sys.argv[3])
    elif cmd == "expand":
        cmd_expand(spec, *sys.argv[3:7])
    else:
        die("unknown command " + cmd)
