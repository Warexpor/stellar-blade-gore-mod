# compose.py out.obj side(+1|-1) face.obj hair.obj tail.obj : her face half (sbslice's), the hair clipped along y=0
# (a preview, triangles wholly on the kept side), the ponytail whole on the side of its root, all in her frame
import sys
out, side, face, hair, tail = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
HEAD = (0.1, 0.0, 151.8)
def load(f):
    v, t = [], []
    for l in open(f):
        if l.startswith('v '): v.append(tuple(map(float, l.split()[1:4])))
        elif l.startswith('f '): t.append(tuple(int(x) - 1 for x in l.split()[1:4]))
    return v, t
parts = []
fv, ft = load(face); parts.append(('face', fv, ft))
hv, ht = load(hair); hv = [(x + HEAD[0], y + HEAD[1], z + HEAD[2]) for x, y, z in hv]
ht = [t for t in ht if all(hv[i][1] * side >= -0.2 for i in t)]
parts.append(('hair', hv, ht))
tv, tt = load(tail)
import os
TX = os.environ.get('TAILX', 'flip')
if TX == 'flip': tv = [(-x + HEAD[0], -y + HEAD[1], z + HEAD[2]) for x, y, z in tv]
else: tv = [(x + HEAD[0], y + HEAD[1], z + HEAD[2]) for x, y, z in tv]
root_y = sum(p[1] for p in tv[:200]) / 200
if root_y * side >= 0 or os.environ.get('TAILBOTH'): parts.append(('tail', tv, tt))
with open(out, 'w') as o:
    base = 0
    for name, v, t in parts:
        o.write(f'o {name}\n')
        for p in v: o.write('v %.3f %.3f %.3f\n' % p)
        for a, b, c in t: o.write(f'f {a+base+1} {b+base+1} {c+base+1}\n')
        base += len(v)
print(out, [(n, len(t)) for n, v, t in parts])
