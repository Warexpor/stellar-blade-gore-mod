#!/usr/bin/env python3
"""Hold physfix.lua's runtime outfit fix to the data mod's: for every physics asset the build patched (the cache's
expanded spec), the vanilla asset is made up for Lua (parity.lua), physfix.lua fixes it, and every value it leaves on
the main bodies and joints must be the build's (.cache/work/json_out), its collision table every pair of bodies (the
build's, see the "t" command), and the joints it adds ("j") the ones the build gives its loose bodies, frame for frame.

  parity.py <cache work dir> <Scripts dir> <scratch dir>
"""
import json, math, os, subprocess, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../assetkit"))
from outfits import world_pose  # noqa: E402
from patch_shows import physics_bodies, disable_table, main_export  # noqa: E402

work, scripts, scratch = sys.argv[1:4]
MOTION = {"ACM_Free": 0, "ACM_Limited": 1, "ACM_Locked": 2}


def props(lst):
    return {p["Name"]: p for p in lst or []}


def value(p, default):
    if p is None:
        return default
    v = p["Value"]
    if isinstance(v, list):
        v = v[0]["Value"]
    if isinstance(v, dict):
        return [float(v["X"]), float(v["Y"]), float(v["Z"])]
    if isinstance(v, str) and "ACM_" in v:
        return MOTION[v.split("::")[-1]]
    return v


def joints(d):
    m = main_export(d)[1]
    out = []
    for ref in next((p for p in m["Data"] if p["Name"] == "ConstraintSetup"), {"Value": []})["Value"]:
        inst = props(next(p for p in d["Exports"][ref["Value"] - 1]["Data"] if p["Name"] == "DefaultInstance")["Value"])
        prof = props(inst["ProfileInstance"]["Value"]) if "ProfileInstance" in inst else {}
        cone = props(prof["ConeLimit"]["Value"]) if "ConeLimit" in prof else {}
        tw = props(prof["TwistLimit"]["Value"]) if "TwistLimit" in prof else {}
        out.append({
            "child": inst["ConstraintBone1"]["Value"], "parent": inst["ConstraintBone2"]["Value"],
            "pri1": value(inst.get("PriAxis1"), [1.0, 0.0, 0.0]), "sec1": value(inst.get("SecAxis1"), [0.0, 1.0, 0.0]),
            "pri2": value(inst.get("PriAxis2"), [1.0, 0.0, 0.0]), "sec2": value(inst.get("SecAxis2"), [0.0, 1.0, 0.0]),
            # the engine's defaults where the asset leaves them (FConeConstraint / FTwistConstraint)
            "cone": {"Swing1Motion": value(cone.get("Swing1Motion"), 0), "Swing2Motion": value(cone.get("Swing2Motion"), 0),
                     "Swing1LimitDegrees": float(value(cone.get("Swing1LimitDegrees"), 45.0)),
                     "Swing2LimitDegrees": float(value(cone.get("Swing2LimitDegrees"), 45.0)),
                     "bSoftConstraint": bool(value(cone.get("bSoftConstraint"), True))},
            "twist": {"TwistMotion": value(tw.get("TwistMotion"), 0), "TwistLimitDegrees": float(value(tw.get("TwistLimitDegrees"), 45.0)),
                      "bSoftConstraint": bool(value(tw.get("bSoftConstraint"), True))},
        })
    return out


def bodies(d):
    out = []
    for e, bone in physics_bodies(d):
        inst = props(next((p for p in e["Data"] if p["Name"] == "DefaultInstance"), {"Value": []})["Value"])
        out.append({"bone": bone, "lin": float(value(inst.get("LinearDamping"), 0.01)), "ang": float(value(inst.get("AngularDamping"), 0.0))})
    return out


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    return "{" + ", ".join(f"[{json.dumps(k)}] = {lua(x)}" for k, x in v.items()) + "}"


spec = json.load(open(f"{work}/spec.json"))
mesh_of = {}
for line in open(f"{work}/outfits/pairs.txt"):
    mesh, phys = line.split()
    if phys != "-":
        mesh_of.setdefault(phys, mesh)
assets = sorted(k for k, v in spec["assets"].items() if v.get("mode") == "physics")
os.makedirs(scratch, exist_ok=True)
files, want = [], {}
for phys in assets:
    van, out = json.load(open(f"{work}/json/{phys}.json")), json.load(open(f"{work}/json_out/{phys}.json"))
    bones = json.load(open(f"{work}/outfits/bones/SB/Content/{mesh_of[phys]}.json"))["bones"]
    R, T = world_pose(bones)
    names = [b["name"] for b in bones]
    data = {"name": phys.rsplit("/", 1)[1], "bodies": bodies(van), "cons": joints(van),
            "bones": {b["name"]: {"i": i, "parent": names[b["parent"]] if b["parent"] >= 0 else "None", "q": list(R[i]), "t": list(T[i])}
                      for i, b in enumerate(bones)}}
    f = f"{scratch}/{data['name']}.lua"
    open(f, "w").write("return " + lua(data) + "\n")
    files.append(f)
    table, _ = disable_table(out)
    want[data["name"]] = {"bodies": bodies(out), "cons": joints(out), "n": len(physics_bodies(out)), "table": table,
                          "joints": {j["child"]: j for j in spec["assets"][phys]["joints"]}}

res = subprocess.run(["lua", os.path.join(os.path.dirname(os.path.abspath(__file__)), "parity.lua"), scripts] + files,
                     capture_output=True, text=True)
if res.returncode:
    sys.exit("parity.lua failed:\n" + res.stderr)
MAIN = {b for g in spec["outfits"]["groups"].values() for b in g}
bad, got, cur = 0, {}, None
for line in res.stdout.splitlines():
    f = line.split(" ")
    if f[0] == "F":
        cur = got.setdefault(f[1], {"B": {}, "C": {}, "J": {}, "L": [], "what": " ".join(f[2:])})
    elif f[0] == "B":
        cur["B"][f[1]] = (float(f[2]), float(f[3]))
    elif f[0] == "C":
        cur["C"].setdefault(f[1], []).append(f[2:])
    elif f[0] == "T":
        cur["T"] = None if f[1] == "nil" else int(f[1])
    elif f[0] == "J":
        cur["J"][f[1]] = {"parent": f[2], "name": f[3], "pos": [float(x) for x in f[4:7]], "pri": [float(x) for x in f[7:10]],
                          "sec": [float(x) for x in f[10:13]], "motions": f[13], "nocoll": f[14] == "true"}
    elif f[0] == "L":
        cur["L"].append((f[1], f[2]))


def close(a, b, tol):
    return abs(a - b) <= tol


for name, w in want.items():
    g = got.get(name)
    errs = []
    if not g:
        errs.append("no answer")
    else:
        for b in w["bodies"]:
            if b["bone"] in MAIN:
                lin, ang = g["B"][b["bone"]]
                if not (close(lin, b["lin"], 1e-5) and close(ang, b["ang"], 1e-5)):
                    errs.append(f"{b['bone']} damping {lin}/{ang}, build {b['lin']}/{b['ang']}")
        seen = {}
        for c in w["cons"]:
            if c["child"] not in MAIN:
                continue
            k = seen[c["child"]] = seen.get(c["child"], -1) + 1
            v = g["C"][c["child"]][k]
            mine = (int(v[0]), int(v[1]), float(v[2]), float(v[3]), v[4] == "true", int(v[5]), float(v[6]), v[7] == "true", [float(x) for x in v[8:11]], [float(x) for x in v[11:14]])
            cc, tw = c["cone"], c["twist"]
            theirs = (cc["Swing1Motion"], cc["Swing2Motion"], cc["Swing1LimitDegrees"], cc["Swing2LimitDegrees"], cc["bSoftConstraint"],
                      tw["TwistMotion"], tw["TwistLimitDegrees"], tw["bSoftConstraint"], c["sec2"], c["pri2"])
            ok = mine[:2] == theirs[:2] and mine[4] == theirs[4] and mine[5] == theirs[5] and mine[7] == theirs[7] \
                and close(mine[2], theirs[2], 1e-3) and close(mine[3], theirs[3], 1e-3) and close(mine[6], theirs[6], 1e-3) \
                and all(close(a, b, 2e-5) for k in (8, 9) for a, b in zip(mine[k], theirs[k]))
            if not ok:
                errs.append(f"{c['child']} joint {mine}, build {theirs}")
        n = w["n"]
        if g.get("T") != n or w["table"] != {(a, b) for a in range(n) for b in range(a + 1, n)}:
            errs.append(f"table: asked for {g.get('T')} bodies of {n} (the build's has {len(w['table'])} pairs)")
        if sorted(g["J"]) != sorted(w["joints"]):
            errs.append(f"jointed {sorted(g['J'])}, build {sorted(w['joints'])}")
        for b, j in w["joints"].items():
            m = g["J"].get(b)
            if m and not (m["parent"] == j["parent"] and m["name"] == b and m["motions"] == "222222" and m["nocoll"]
                          and all(close(x, y, 1e-3) for x, y in zip(m["pos"], j["pos"]))
                          and all(close(x, y, 1e-5) for k in ("pri", "sec") for x, y in zip(m[k], j[k]))):
                errs.append(f"{b} joint {m}, build {j}")
        if g["L"]:
            errs.append(f"still loose: {g['L']}")
    print(f"{'ok ' if not errs else 'BAD'} {name}" + ("" if not errs else ": " + "; ".join(errs[:4]) + (f" (+{len(errs) - 4})" if len(errs) > 4 else "")))
    bad += bool(errs)
print(f"physics parity: {len(want) - bad} of {len(want)} assets as the build makes them")
sys.exit(1 if bad else 0)
