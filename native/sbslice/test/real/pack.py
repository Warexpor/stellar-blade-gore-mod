#!/usr/bin/env python3
"""Pack a meshtool dump (LOD0) into the binary the real-mesh harness reads.

  pack.py <meshtool dump.json> <out.bin>

Layout (little endian): nb nv nsec nidx (int32); per bone: parent (int32), local FTransform (12 floats: quat xyzw,
translation, pad, scale, pad), name (32 bytes); per section: base, count, nbmap (int32), BoneMap (uint16 x nbmap);
positions (3 floats per vertex); weights (8 section-local indices, then 8 weights, uint8); indices (uint32).
"""
import base64
import json
import struct
import sys

import array

d = json.load(open(sys.argv[1]))
lod = d["lods"][0]
bones = d["bones"]
nv = lod["numVertices"]
secs = lod["sections"]
idx = array.array("I")
raw = base64.b64decode(lod["indices"])
idx.frombytes(raw) if len(raw) == 4 * (len(raw) // 4) and len(raw) // 4 >= 3 else None
pos = array.array("f"); pos.frombytes(base64.b64decode(lod["positions"]))
ib = array.array("h"); ib.frombytes(base64.b64decode(lod["infBones"]))
iw = base64.b64decode(lod["infWeights"])
out = bytearray(struct.pack("<4i", len(bones), nv, len(secs), len(idx)))
for b in bones:
    out += struct.pack("<i", b["parent"]) + struct.pack("<12f", *b["rot"], *b["loc"], 0, 1, 1, 1, 0)
    out += b["name"].encode()[:31].ljust(32, b"\0")
secof = [0] * nv
for s, sec in enumerate(secs):
    out += struct.pack("<3i", sec["baseVertex"], sec["numVertices"], len(sec["boneMap"]))
    out += struct.pack("<%dH" % len(sec["boneMap"]), *sec["boneMap"])
    for v in range(sec["baseVertex"], sec["baseVertex"] + sec["numVertices"]):
        secof[v] = s
out += pos.tobytes()
inv = [{m: i for i, m in enumerate(sec["boneMap"])} for sec in secs]
bad = 0
for v in range(nv):
    li, lw = [0] * 8, [0] * 8
    for k in range(8):
        w = iw[v * 8 + k]
        if not w:
            continue
        m = ib[v * 8 + k]
        if m not in inv[secof[v]]:
            bad += 1
            continue
        li[k], lw[k] = inv[secof[v]][m], w
    t = sum(lw)
    if t and t != 255:  # meshtool rounds 16-bit weights down: give the rest to the strongest
        lw[lw.index(max(lw))] += 255 - t
    out += bytes(li) + bytes(lw)
out += idx.tobytes()
open(sys.argv[2], "wb").write(out)
print(f"{len(bones)} bones, {nv} verts, {len(secs)} sections, {len(idx) // 3} triangles, {bad} unmapped weights")
