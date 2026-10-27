#!/usr/bin/env python3
"""Pictures of the regrow harness's OBJs (real_split REGROW=1 REGROWOBJ=<prefix>): each stage's two meshes, her grey,
the copy orange, from the front, her right and above, a numpy z-buffer (no Blender needed).

  render.py <prefix> [out.png]   stages cut, dissolve, fade, end, one row each
ZOOM=1: close on the part (the dissolving copy's box, half again round it)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

pre = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else pre + ".png"
W = 360
VIEWS = [("side", np.array([0, -1, 0.0])), ("front", np.array([-1, 0, 0.0])), ("top", np.array([0, -0.3, 1.0]))]


def load(fn):
    vs, fs = [], []
    for line in open(fn):
        if line.startswith("v "):
            vs.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("f "):
            fs.append([int(x) - 1 for x in line.split()[1:4]])
    return np.array(vs, float), np.array(fs, int).reshape(-1, 3)


def frame(d):
    d = d / np.linalg.norm(d)
    up = np.array([0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([0, 1.0, 0])
    r = np.cross(up, d); r /= np.linalg.norm(r)
    u = np.cross(d, r)
    return r, u, d


def draw(meshes, d, box):
    r, u, f = frame(d)
    img = np.full((W, W, 3), 245, np.uint8)
    z = np.full((W, W), -1e30)
    c0, size = box
    for (v, t, col) in meshes:
        if not len(t):
            continue
        p = v - c0
        x = (p @ r / size + 0.5) * W
        y = (0.5 - p @ u / size) * W
        dep = -(p @ f)
        a, b, c = t[:, 0], t[:, 1], t[:, 2]
        n = np.cross(v[b] - v[a], v[c] - v[a])
        nl = np.linalg.norm(n, axis=1) + 1e-9
        shade = 0.35 + 0.65 * np.abs(n @ f) / nl
        for i in range(len(t)):
            xs, ys = x[t[i]], y[t[i]]
            x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
            y0, y1 = int(max(0, np.floor(ys.min()))), int(min(W - 1, np.ceil(ys.max())))
            if x0 > x1 or y0 > y1:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, bx, cx), (ay, by, cy) = xs, ys
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-12:
                continue
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
            l3 = 1 - l1 - l2
            m = (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
            if not m.any():
                continue
            zz = l1 * dep[t[i][0]] + l2 * dep[t[i][1]] + l3 * dep[t[i][2]]
            sub = z[y0:y1 + 1, x0:x1 + 1]
            m &= zz > sub
            sub[m] = zz[m]
            img[y0:y1 + 1, x0:x1 + 1][m] = (np.array(col) * shade[i]).astype(np.uint8)
    return img


stages = [s for s in ("cut", "dissolve", "fade", "end") if os.path.exists(f"{pre}_{s}_her.obj")]
rows = []
box = None
if os.environ.get("ZOOM") and os.path.exists(f"{pre}_dissolve_copy.obj"):
    v, t = load(f"{pre}_dissolve_copy.obj")
    used = v[np.unique(t)] if len(t) else v
    lo, hi = used.min(0), used.max(0)
    box = ((lo + hi) / 2, (hi - lo).max() * 1.5)
for s in stages:
    her = load(f"{pre}_{s}_her.obj")
    cp = load(f"{pre}_{s}_copy.obj") if os.path.exists(f"{pre}_{s}_copy.obj") else (np.zeros((0, 3)), np.zeros((0, 3), int))
    if box is None:
        lo, hi = her[0].min(0), her[0].max(0)
        box = ((lo + hi) / 2, (hi - lo).max() * 1.05)
    ims = [draw([(her[0], her[1], (190, 190, 200)), (cp[0], cp[1], (255, 140, 30))], d, box) for _, d in VIEWS]
    row = Image.fromarray(np.concatenate(ims, 1))
    ImageDraw.Draw(row).text((6, 6), s, fill=(0, 0, 0))
    rows.append(row)
sheet = Image.new("RGB", (W * len(VIEWS), W * len(rows)), "white")
for i, r in enumerate(rows):
    sheet.paste(r, (0, i * W))
sheet.save(out)
print(out)
