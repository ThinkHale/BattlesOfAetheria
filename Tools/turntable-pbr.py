# Blender: four-side EEVEE preview of a GLB (with its PBR materials).
#   blender -b --factory-startup -P Tools/turntable-pbr.py -- model.glb out_prefix
import bpy, sys, math, numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.gltf(filepath=argv[0]); sc = bpy.context.scene
ms = [o for o in sc.objects if o.type == 'MESH' and len(o.data.vertices) > 100]
pts = np.array([tuple(o.matrix_world @ Vector(c)) for o in ms for c in o.bound_box]); mn, mx = pts.min(0), pts.max(0)
ctr = Vector((mn + mx) / 2); size = float((mx - mn).max())
print('DIMS', np.round(mx - mn, 3), 'tris', sum(len(p.vertices) - 2 for o in ms for p in o.data.polygons))
sc.render.engine = 'BLENDER_EEVEE'; sc.render.resolution_x = sc.render.resolution_y = 640; sc.view_settings.view_transform = 'AgX'
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.3, 0.3, 0.32, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.7
for n, e, r in (('k', 3.5, (50, 0, -35)), ('r', 2.5, (60, 0, 150)), ('f', 0.6, (70, 0, -140))):
    l = bpy.data.lights.new(n, 'SUN'); l.energy = e; o = bpy.data.objects.new(n, l); sc.collection.objects.link(o); o.rotation_euler = [math.radians(a) for a in r]
cam = bpy.data.objects.new('c', bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera = cam; cam.data.type = 'ORTHO'; cam.data.ortho_scale = size * 1.05
for i, az in enumerate([0, 90, 180, 270]):
    a = math.radians(az); cam.location = ctr + Vector((math.sin(a) * -5, math.cos(a) * -5, 0))
    cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f'{argv[1]}_{i}.png'; bpy.ops.render.render(write_still=True)
