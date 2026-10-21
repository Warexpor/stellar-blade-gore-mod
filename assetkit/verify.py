#!/usr/bin/env python3
"""Check the repacked assets: ragdoll keys reach the player, and nothing else changed.

Usage: verify.py <spec.json> <vanilla_json_dir> <repacked_json_dir> [--no-meshes]
--no-meshes: "cpuaccess" jobs were checked by sbtool checkcpu (meshes have no JSON then).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_shows import response_array, physics_table, disable_table, physics_bodies, joint_names, voice_pairs, notify_events, main_export
import base64

spec = json.load(open(sys.argv[1]))
van_dir, out_dir = sys.argv[2], sys.argv[3]
no_meshes = "--no-meshes" in sys.argv[4:]
fail = []


def load(base, rel):
    return json.load(open(os.path.join(base, rel + ".json")))


def cls_name(d, e):
    return d["Imports"][-e["ClassIndex"] - 1]["ObjectName"] if e["ClassIndex"] < 0 else "?"


def props(e):
    return {p["Name"]: p for p in e.get("Data") or []}


for rel, job in spec["assets"].items():
    if no_meshes and job["mode"] == "cpuaccess":
        continue
    v = load(os.environ["SB_VENDOR_JSON"], rel) if job["mode"] == "vendor" else load(van_dir, job.get("from", rel))
    o = load(out_dir, rel)
    tag = f"{job['mode']:6s} {rel}"
    if job["mode"] == "vendor":
        # the third-party package as shipped: same exports, same data
        same = [(e.get("ObjectName"), json.dumps(e.get("Data")), json.dumps(e.get("Extras"))) for e in o["Exports"]] == \
               [(e.get("ObjectName"), json.dumps(e.get("Data")), json.dumps(e.get("Extras"))) for e in v["Exports"]]
        if not same:
            fail.append(f"{tag}: differs from {job['file']}")
        print(f"ok  {tag}  from {job['file']}")
        continue

    if job["mode"] == "voice":
        vp = {k["Value"]: json.dumps(x) for k, x in voice_pairs(v)}
        op = {k["Value"]: x for k, x in voice_pairs(o)}
        for key, want in job["voices"].items():
            got = {q["Name"]: q.get("Value") for q in op.get(key, {"Value": []})["Value"]}
            like = {q["Name"]: q.get("Value") for q in json.loads(vp[want["like"]])["Value"]}
            if not got:
                fail.append(f"{tag}: no voice {key}")
                continue
            snd = got["SoundSource"]
            snd_name = o["Imports"][-snd - 1]["ObjectName"] if isinstance(snd, int) and snd < 0 else None
            if snd_name == "UnknownExport" and os.environ.get("SB_PATCHED_JSON"):
                # the read-back only sees the mod container, so game imports come back unnamed; the import slot
                # survives packing, so name it from the patched package
                snd_name = load(os.environ["SB_PATCHED_JSON"], rel)["Imports"][-snd - 1]["ObjectName"]
            if "sound" in want and snd_name != want["sound"].rsplit("/", 1)[1]:
                fail.append(f"{tag}: {key} plays {snd_name}")
            for k, x in got.items():
                exp = want.get("set", {}).get(k, like[k])
                if k != "SoundSource" and not (x == exp or (isinstance(x, float) and abs(x - exp) < 1e-6)):
                    fail.append(f"{tag}: {key}.{k}={x}")
        if {k: x for k, x in vp.items()} != {k: json.dumps(x) for k, x in op.items() if k not in job["voices"]}:
            fail.append(f"{tag}: other voices changed")
        print(f"ok  {tag}  {', '.join(job['voices'])}")
        continue

    if job["mode"] == "notify":
        _, vm = main_export(v)
        _, om = main_export(o)
        ve, oe = notify_events(vm)["Value"], notify_events(om)["Value"]
        fields = lambda ev: {q["Name"]: q.get("Value") for q in ev["Value"]}
        vex = {e["ObjectName"]: e for e in v["Exports"]}
        name_of = lambda d, i: d["Exports"][i - 1]["ObjectName"]
        old = sorted((name_of(v, fields(e)["Notify"]), round(fields(e)["LinkValue"], 4)) for e in ve)
        kept = sorted((name_of(o, fields(e)["Notify"]), round(fields(e)["LinkValue"], 4)) for e in oe
                      if name_of(o, fields(e)["Notify"]) in vex)
        new = [fields(e) for e in oe if name_of(o, fields(e)["Notify"]) not in vex]
        if kept != old:
            fail.append(f"{tag}: vanilla notifies changed")
        if len(new) != 1 or abs(new[0]["LinkValue"] - job["at"]) > 1e-4:
            fail.append(f"{tag}: {len(new)} new notifies")
        else:
            ne = o["Exports"][new[0]["Notify"] - 1]
            if cls_name(o, ne) != "SBAnimNotify_CharSESound" or props(ne).get("VoiceKey", {}).get("Value") != job["voice"]:
                fail.append(f"{tag}: new notify is not a {job['voice']} voice")
        for e in o["Exports"]:
            if e["OuterIndex"] != 0 and e["ObjectName"] in vex and json.dumps(e.get("Data")) != json.dumps(vex[e["ObjectName"]].get("Data")):
                fail.append(f"{tag}: export {e['ObjectName']} changed")
        strip = lambda e: [p for p in e["Data"] if p["Name"] != "Notifies"]
        if json.dumps(strip(om)) != json.dumps(strip(vm)) or om.get("Extras") != vm.get("Extras"):
            fail.append(f"{tag}: sequence changed beyond its notifies")
        print(f"ok  {tag}  {job['voice']} at {job['at']} s, {len(old)} notifies kept")
        continue
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
        joints = job.get("joints", [])
        if joint_names(o) != joint_names(v) + [j["child"] for j in joints]:
            fail.append(f"{tag}: constraints {joint_names(o)[len(joint_names(v)):]} instead of the spec's joints")
        added = [e for e in o["Exports"] if e["ObjectName"] not in vex]
        for e, j in zip(added, joints):
            inst = {p["Name"]: p["Value"] for p in e["Data"][0]["Value"]}
            prof = {p["Name"]: p["Value"] for p in inst["ProfileInstance"]}
            motions = [q["Value"] for k in ("ConeLimit", "TwistLimit") for q in prof[k]]
            if (inst["ConstraintBone1"], inst["ConstraintBone2"]) != (j["child"], j["parent"]) or set(motions) != {"ACM_Locked"}:
                fail.append(f"{tag}: joint {e['ObjectName']} is not a locked {j['child']} -> {j['parent']}")
        if len(added) != len(joints):
            fail.append(f"{tag}: {len(added)} new exports for {len(joints)} joints")
        for e in o["Exports"]:
            if id(e) in touched or e["OuterIndex"] == 0 or e["ObjectName"] not in vex:
                continue
            if json.dumps(e.get("Data")) != json.dumps(vex[e["ObjectName"]].get("Data")):
                fail.append(f"{tag}: export {e['ObjectName']} changed")
        for e in o["Exports"]:
            if id(e) in touched:
                strip = lambda x: [p for p in x["Data"] if p["Name"] != "DefaultInstance"]
                if json.dumps(strip(e)) != json.dumps(strip(vex[e["ObjectName"]])):
                    fail.append(f"{tag}: {e['ObjectName']} changed beyond DefaultInstance")
        old, _ = disable_table(v)
        print(f"ok  {tag}  {len(old)} -> {len(got)} non-colliding pairs, body {job.get('body', {})}"
              + (f", locked {','.join(j['child'] for j in joints)}" if joints else ""))
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
