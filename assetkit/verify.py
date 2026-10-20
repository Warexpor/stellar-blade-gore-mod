#!/usr/bin/env python3
"""Check the repacked assets: ragdoll keys reach the player, and nothing else changed.

Usage: verify.py <spec.json> <vanilla_json_dir> <repacked_json_dir>
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_shows import response_array, physics_table, disable_table, physics_bodies
import base64

spec = json.load(open(sys.argv[1]))
van_dir, out_dir = sys.argv[2], sys.argv[3]
fail = []


def load(base, rel):
    return json.load(open(os.path.join(base, rel + ".json")))


def cls_name(d, e):
    return d["Imports"][-e["ClassIndex"] - 1]["ObjectName"] if e["ClassIndex"] < 0 else "?"


def props(e):
    return {p["Name"]: p for p in e.get("Data") or []}


for rel, job in spec["assets"].items():
    v, o = load(van_dir, job.get("from", rel)), load(out_dir, rel)
    tag = f"{job['mode']:6s} {rel}"
    if job["mode"] == "table":
        rows = {r["Name"]: {p["Name"]: p.get("Value") for p in r["Value"]} for r in o["Exports"][0]["Table"]["Data"]}
        for row, fields in job["rows"].items():
            for k, want in fields.items():
                if rows[row][k] != want:
                    fail.append(f"{tag}: {row}.{k}={rows[row][k]!r}")
        vrows = {r["Name"]: r for r in v["Exports"][0]["Table"]["Data"]}
        changed = [r["Name"] for r in o["Exports"][0]["Table"]["Data"]
                   if r["Name"] not in job["rows"] and json.dumps(r) != json.dumps(vrows[r["Name"]])]
        if changed:
            fail.append(f"{tag}: unexpected row changes {changed}")
        print(f"ok  {tag}")
        continue

    if job["mode"] == "physics":
        got, _ = disable_table(o)
        if got != physics_table(v, job):
            fail.append(f"{tag}: CollisionDisableTable differs from the spec")
        want = {b for g in job["groups"].values() for b in g}
        for (ve, bone), (oe, _) in zip(physics_bodies(v), physics_bodies(o)):
            inst = lambda e: next((p["Value"] for p in e["Data"] if p["Name"] == "DefaultInstance"), [])  # absent = all defaults
            vi = {p["Name"]: p for p in inst(ve)}
            oi = {p["Name"]: p for p in inst(oe)}
            if set(oi) != set(vi):
                fail.append(f"{tag}: {bone} DefaultInstance fields {sorted(set(oi) ^ set(vi))} added or lost")
                continue
            for k in oi:
                exp = job.get("body", {}).get(k, vi[k]["Value"]) if bone in want else vi[k]["Value"]
                same = oi[k]["Value"] == exp or (isinstance(exp, (int, float)) and isinstance(oi[k]["Value"], (int, float))
                                                  and abs(oi[k]["Value"] - exp) < 1e-5)
                if not same:
                    fail.append(f"{tag}: {bone}.{k}={oi[k]['Value']}")
        touched = {id(oe) for oe, b in physics_bodies(o) if b in want}
        vex = {e["ObjectName"]: e for e in v["Exports"]}
        for e in o["Exports"]:
            if id(e) in touched or e["OuterIndex"] == 0:
                continue
            if json.dumps(e.get("Data")) != json.dumps(vex[e["ObjectName"]].get("Data")):
                fail.append(f"{tag}: export {e['ObjectName']} changed")
        for e in o["Exports"]:
            if id(e) in touched:
                strip = lambda x: [p for p in x["Data"] if p["Name"] != "DefaultInstance"]
                if json.dumps(strip(e)) != json.dumps(strip(vex[e["ObjectName"]])):
                    fail.append(f"{tag}: {e['ObjectName']} changed beyond DefaultInstance")
        old, _ = disable_table(v)
        print(f"ok  {tag}  {len(old)} -> {len(got)} non-colliding pairs, body {job.get('body', {})}")
        continue

    if job["mode"] == "cpuaccess":
        def lodinfo(x):
            e = next(e for e in x["Exports"] if e["OuterIndex"] == 0)
            return e, next(p for p in e["Data"] if p["Name"] == "LODInfo")["Value"]
        (ve, vl), (oe, ol) = lodinfo(v), lodinfo(o)
        for i, lod in enumerate(ol):
            got = next(p for p in lod["Value"] if p["Name"] == "bAllowCPUAccess")["Value"]
            want = True if i in job.get("lods", [0]) else next(p for p in vl[i]["Value"] if p["Name"] == "bAllowCPUAccess")["Value"]
            if got != want:
                fail.append(f"{tag}: LOD{i} bAllowCPUAccess={got}")
        strip = lambda e: [p for p in e["Data"] if p["Name"] != "LODInfo"]
        if json.dumps(strip(oe)) != json.dumps(strip(ve)) or oe.get("Extras") != ve.get("Extras"):
            fail.append(f"{tag}: mesh changed beyond bAllowCPUAccess")
        print(f"ok  {tag}  LOD{job.get('lods', [0])} CPU access")
        continue

    if job["mode"] == "collision":
        vex = {e["ObjectName"]: e for e in v["Exports"]}
        for e in o["Exports"]:
            want = job["ignore"].get(e["ObjectName"])
            if want is None:
                if json.dumps(e.get("Data")) != json.dumps(vex[e["ObjectName"]].get("Data")):
                    fail.append(f"{tag}: export {e['ObjectName']} changed")
                continue
            got = {ch: r for _, ch, r in response_array(base64.b64decode(e["Data"]), o["NameMap"])[1]}
            old = {ch: r for _, ch, r in response_array(base64.b64decode(vex[e["ObjectName"]]["Data"]), v["NameMap"])[1]}
            for ch in want:
                if got.get(ch) != 0:
                    fail.append(f"{tag}: {e['ObjectName']} does not ignore {ch}")
            if {k: r for k, r in got.items() if k not in want} != {k: r for k, r in old.items() if k not in want}:
                fail.append(f"{tag}: {e['ObjectName']} other responses changed")
        print(f"ok  {tag}  {', '.join(f'{c}: ignore {w}' for c, w in job['ignore'].items())}")
        continue

    rag = [e for e in o["Exports"] if cls_name(o, e) == "SBShowRagdollKey"]
    if not rag:
        fail.append(f"{tag}: no ragdoll key after patch")
    for e in rag:
        p = props(e).get("bIgnorePlayer")
        if not p or p["Value"] is not False:
            fail.append(f"{tag}: {e['ObjectName']} bIgnorePlayer not false")

    main = next(e for e in o["Exports"] if e["OuterIndex"] == 0)
    if job["mode"] == "clone" and main["ObjectName"] != rel.rsplit("/", 1)[1]:
        fail.append(f"{tag}: clone main export is {main['ObjectName']}")
    for e in rag:
        lim = props(e).get("ImpulseLimitVelocity")
        if not lim or not lim["Value"] or float(lim["Value"]) > 1000:
            fail.append(f"{tag}: {e['ObjectName']} has no sane ImpulseLimitVelocity")
        cap = props(e).get("CapsuleComponentFollowingSocketName")
        if not cap or cap["Value"] is not None:
            fail.append(f"{tag}: {e['ObjectName']} still drags the capsule along")
    chans = {k["Value"]: [x["Value"] for x in (c["Value"][0]["Value"] or [])]
             for k, c in props(main)["KeyContanerMap"]["Value"]}
    rag_idx = [i for i, e in enumerate(o["Exports"], 1) if cls_name(o, e) == "SBShowRagdollKey"]
    if not set(rag_idx) <= set(chans.get(23, [])):
        fail.append(f"{tag}: ragdoll key not wired into channel 23 ({chans.get(23)})")

    vex = {e["ObjectName"]: e for e in v["Exports"]}
    for e in o["Exports"]:
        if cls_name(o, e) == "SBShowRagdollKey" or e is main:
            continue
        if e["ObjectName"] not in vex:
            fail.append(f"{tag}: unexpected new export {e['ObjectName']}")
        elif json.dumps(e.get("Data")) != json.dumps(vex[e["ObjectName"]].get("Data")):
            fail.append(f"{tag}: export {e['ObjectName']} changed")
    vmain = next(e for e in v["Exports"] if e["OuterIndex"] == 0)
    for k in props(vmain):
        if k != "KeyContanerMap" and json.dumps(props(vmain)[k]) != json.dumps(props(main).get(k)):
            fail.append(f"{tag}: main field {k} changed")
    print(f"ok  {tag}  ragdoll keys={len(rag)} ch23={chans.get(23)}")

if fail:
    print("\nVERIFY FAILED:\n  " + "\n  ".join(fail))
    sys.exit(1)
print("verify: all assets ok")
