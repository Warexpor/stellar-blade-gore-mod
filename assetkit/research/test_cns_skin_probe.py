#!/usr/bin/env python3
"""Small analytic fixture: a 180-degree turn moves a weighted vertex 2 cm."""
import base64
import json
import pathlib
import struct
import subprocess
import sys
import tempfile


def encoded(fmt, *values):
    return base64.b64encode(struct.pack(fmt, *values)).decode()


def main():
    identity = [0, 0, 0, 1]
    mesh = {'bones': [
        {'name': 'root', 'parent': -1, 'rot': identity, 'loc': [0, 0, 0]},
        {'name': 'Ab-L-Breast-Link', 'parent': 0, 'rot': identity, 'loc': [0, 0, 0]},
        {'name': 'Ab-L-Breast', 'parent': 1, 'rot': identity, 'loc': [0, 0, 0]},
    ], 'lods': [{'numVertices': 2, 'positions': encoded('<6f', 1, 0, 0, 1, 0, 0),
                 'infBones': encoded('<16h', 2, *([-1] * 7), 0, *([-1] * 7)),
                 'infWeights': encoded('<16B', 255, *([0] * 7), 255, *([0] * 7))}]}
    log = '[00:00:00] breast probe 3 s L: Ab-L-Breast-Link parent=Dm-L-Breast d=0.00 q=(0,0,1,0)\n'
    with tempfile.TemporaryDirectory() as d:
        path = pathlib.Path(d)
        (path / 'mesh.json').write_text(json.dumps(mesh))
        (path / 'log').write_text(log)
        result = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('cns_skin_probe.py')),
                                 str(path / 'mesh.json'), str(path / 'log')],
                                text=True, capture_output=True, check=True).stdout
    assert 'Link rotation from reference: 180.0 degrees' in result, result
    assert 'Vertices influenced by link subtree: 1 ' in result, result
    assert 'median 2.00, p90 2.00, max 2.00' in result, result
    print('PASS: weighted vertex moves 2 cm; unrelated vertex is excluded')


if __name__ == '__main__':
    main()
