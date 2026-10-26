import bpy, sys, math, mathutils, os
argv = sys.argv[sys.argv.index("--")+1:]
out, srcs = argv[0], argv[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
obs = []
for i, src in enumerate(srcs):
    bpy.ops.wm.obj_import(filepath=src, forward_axis='Y', up_axis='Z')
    ob = bpy.context.selected_objects[0]; obs.append(ob)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'RANDOM' if len(obs) > 1 else 'SINGLE'
sc.display.shading.show_backface_culling = False
sc.render.resolution_x, sc.render.resolution_y = 900, 900
sc.world = bpy.data.worlds.new("w")
pts = [ob.matrix_world @ mathutils.Vector(c) for ob in obs for c in ob.bound_box]
c = sum(pts, mathutils.Vector()) / len(pts)
size = float(os.environ["SIZE"]) if os.environ.get("SIZE") else max(max(p[k] for p in pts) - min(p[k] for p in pts) for k in range(3))
if os.environ.get("CENTER"): c = mathutils.Vector(map(float, os.environ["CENTER"].split(",")))
import os
VIEWS = [("front", 0, 0), ("q34", 50, 15), ("side", 90, 0), ("back34", 200, 20), ("top", 0, 80)] if not os.environ.get("VIEWS") else [(v.split(":")[0], float(v.split(":")[1]), float(v.split(":")[2])) for v in os.environ["VIEWS"].split()]
for name, az, el in VIEWS:
    cam = bpy.data.cameras.new(name); cam.type = 'ORTHO'; cam.ortho_scale = size * 1.15
    co = bpy.data.objects.new(name, cam); sc.collection.objects.link(co)
    a, e = math.radians(az), math.radians(el)
    d = mathutils.Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
    co.location = c + d * 200
    co.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = co
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
