#!/usr/bin/env python3
"""Counterfactual linear skinning probe for an exported CNS mesh and its F7 log.

This is a kinematic mesh calculation, not an Unreal/PhysX simulation. It isolates
one measured link rotation on the bind-pose mesh; it does not model animation,
collisions, joint forces, the link's translation, or the post-process graph. The
older meshtool exports omit reference bone scales; this probe only uses the left
side and checks its ancestor scales when the export includes them.
Usage: python cns_skin_probe.py /path/to/mesh.json /path/to/stellarbladegore.log
"""
import base64
import json
import re
import sys

import numpy as np


def mul(a, b):
    x, y, z, w = a
    X, Y, Z, W = b
    return np.array([w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
                     w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z])


def matrix(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def main(mesh_path, log_path):
    mesh = json.load(open(mesh_path))
    lines = open(log_path).read().splitlines()
    samples = [s for s in lines if 'breast probe 3 s L:' in s]
    if not samples:
        raise SystemExit('No completed 3-second left breast probe in log')
    m = re.search(r'Ab-L-Breast-Link parent=[^ ]+ d=[\d.]+ q=\(([^)]+)\)', samples[-1])
    if not m:
        raise SystemExit('No link quaternion in latest sample')
    q = np.array([float(x) for x in m.group(1).split(',')])
    bones = mesh['bones']
    index = {b['name']: i for i, b in enumerate(bones)}
    link = index['Ab-L-Breast-Link']
    parent = bones[link]['parent']
    k = link
    scales_known = True
    while k >= 0:
        scale = bones[k].get('scale')
        if scale is None:
            scales_known = False
        elif not np.allclose(scale, [1, 1, 1], atol=1e-4):
            raise SystemExit('Non-unit reference scale on link ancestry: ' + bones[k]['name'])
        k = bones[k]['parent']
    # Construct rest transforms through the chain; input quaternions are local.
    world_q, world_p = [], []
    for b in bones:
        p = b['parent']
        localq = np.array(b['rot'], dtype=float)
        localp = np.array(b['loc'], dtype=float)
        world_q.append(mul(world_q[p], localq) if p >= 0 else localq)
        world_p.append(world_p[p] + matrix(world_q[p]) @ localp if p >= 0 else localp)
    descendants = set()
    for i in range(len(bones)):
        k = i
        while k >= 0:
            if k == link:
                descendants.add(i)
                break
            k = bones[k]['parent']
    lod = mesh['lods'][0]
    n = lod['numVertices']
    positions = np.frombuffer(base64.b64decode(lod['positions']), '<f4').reshape(n, 3)
    # meshtool has already converted section-local BoneMap entries to skeleton indices.
    influence = np.frombuffer(base64.b64decode(lod['infBones']), '<i2').reshape(n, 8)
    weights = np.frombuffer(base64.b64decode(lod['infWeights']), 'u1').reshape(n, 8)
    factor = (np.isin(influence, list(descendants)) * weights).sum(axis=1) / 255.0
    affected = factor > 0
    # Reference relative link quaternion can differ from identity; remove it before applying measured rotation.
    rest = np.array(bones[link]['rot'], dtype=float)
    delta = mul(q, rest * np.array([-1, -1, -1, 1]))
    basis = matrix(world_q[parent])
    rotation = basis @ matrix(delta) @ basis.T
    pivot = world_p[link]
    delta_pos = ((positions - pivot) @ rotation.T - (positions - pivot)) * factor[:, None]
    magnitude = np.linalg.norm(delta_pos[affected], axis=1)
    angle = 2 * np.degrees(np.arccos(np.clip(abs(delta[3]) / np.linalg.norm(delta), 0, 1)))
    print('Sample:', samples[-1].split('breast probe')[0].strip())
    print('Link rotation from reference: %.1f degrees' % angle)
    print('Vertices influenced by link subtree: %d (%.1f%% of mesh)' % (affected.sum(), 100 * affected.mean()))
    print('Predicted displacement, rotation only (cm): median %.2f, p90 %.2f, max %.2f' %
          (np.median(magnitude), np.percentile(magnitude, 90), magnitude.max()))
    print('Counterfactual identity rotation: 0 cm by construction')
    if not scales_known:
        print('Warning: reference bone scales not exported; unit link ancestry assumed.')
    print('Limits: bind pose only; no UE physics, animation, translation or collision.')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
