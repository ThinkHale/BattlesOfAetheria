# Blender: a texture-free copy of a Tripo FBX for uploading to Mixamo (the rig only needs the mesh; the 4K textures
# make the file too big to upload from the browser). retarget-mixamo-hero.py puts Tripo's textures back with --maps.
#   blender -b --factory-startup -P Tools/mixamo-prep.py -- tripo.fbx out.fbx
import bpy, sys

src, out = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
for o in [o for o in bpy.data.objects if o.type != 'MESH']: bpy.data.objects.remove(o)
for o in bpy.data.objects: o.data.materials.clear()
for im in list(bpy.data.images): bpy.data.images.remove(im)
bpy.ops.export_scene.fbx(filepath=out, use_selection=False, object_types={'MESH'}, embed_textures=False, path_mode='STRIP')
print('mesh-only FBX ->', out, sum(len(o.data.vertices) for o in bpy.data.objects), 'vertices')
