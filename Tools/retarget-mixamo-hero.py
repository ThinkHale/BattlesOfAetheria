# Blender: turn a Mixamo-rigged hero (e.g. a Tripo body rigged in Mixamo, no clips) into the rigged.blend that
# assemble-meshy-hero.py reads, animated with Meshy clips we already own (retargeted from other heroes' downloads).
#   blender -b --factory-startup -P Tools/retarget-mixamo-hero.py -- mixamo.fbx out/rigged.blend height_m clips.glb [...]
# Bones are renamed to Meshy's names and the finger bones folded into the hands (the assembly bakes fists), so the
# rest of the pipeline treats the hero like a Meshy one. Clip names repeated across files keep the first copy.
import bpy, sys, re, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
fbx, out, HEIGHT, sources = argv[0], argv[1], float(argv[2]), argv[3:]

MIXAMO_TO_MESHY = {'Spine': 'Spine02', 'Spine1': 'Spine01', 'Spine2': 'Spine', 'Neck': 'neck', 'HeadTop_End': 'head_end'}
# Torso bones keep the target's own rest orientation (both rest poses stand upright); limbs are first swung onto the
# source's rest direction, since Mixamo rests in a T-pose and Meshy in an A-pose.
TORSO = ('Hips', 'Spine02', 'Spine01', 'Spine', 'neck', 'Head', 'LeftShoulder', 'RightShoulder')
LIMBS = tuple(s + b for s in ('Left', 'Right') for b in ('Arm', 'ForeArm', 'Hand', 'UpLeg', 'Leg', 'Foot', 'ToeBase'))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
# The FBX sets 30 fps; the Meshy heroes' clips were imported at the factory 24, so keep their frame numbering
# (strips.json ranges and render-strips timing carry over unchanged).
bpy.context.scene.render.fps = 24
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH')
# Mixamo's rest pose can lie on its back, with the one-frame "mixamo.com" pose standing it up. Make that standing
# T-pose the rest pose: bake it into the mesh, apply it to the bones, and bind the mesh again.
if rig.animation_data and rig.animation_data.action: bpy.context.scene.frame_set(int(rig.animation_data.action.frame_range[0]))
bpy.context.view_layer.update()
bpy.context.view_layer.objects.active = body
arm_mod = next(m for m in body.modifiers if m.type == 'ARMATURE'); bpy.ops.object.modifier_apply(modifier=arm_mod.name)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.select_all(action='SELECT'); bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
body.modifiers.new('Armature', 'ARMATURE').object = rig
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
if rig.animation_data:
    for t in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(t)

# Tripo materials arrive miswired: fully metallic, the albedo also used as alpha (and as the normal map when there
# is no real one), a PBR map on Specular (which is why the model looks dull and dark in Mixamo). The textures
# themselves are unchanged; rewire them by their original file names (Color / Normal / *_metallic / *_roughness).
for m in body.data.materials:
    nt = m.node_tree; bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    base = bsdf.inputs['Base Color'].links[0].from_node
    for l in list(nt.links):
        if l.to_node == bsdf and l.to_socket.name != 'Base Color' or l.to_node.type == 'NORMAL_MAP': nt.links.remove(l)
    for n in [n for n in nt.nodes if n.type == 'NORMAL_MAP']: nt.nodes.remove(n)
    bsdf.inputs['Metallic'].default_value = 0.0; bsdf.inputs['Roughness'].default_value = 0.6
    bsdf.inputs['Specular IOR Level'].default_value = 0.5
    base_file = base.image.filepath_raw
    for n in [n for n in nt.nodes if n.type == 'TEX_IMAGE' and n != base]: nt.nodes.remove(n)   # (bpy wrappers: ==, not is)
    # Wire maps by file name; some arrive in the FBX with no node at all (Kepri's metallic map).
    roles = {}
    for img in bpy.data.images:
        f = img.filepath_raw.replace('\\', '/').split('/')[-1].lower()
        if img.filepath_raw == base_file or not img.size[0]: continue
        for role in ('normal', 'metal', 'rough'):
            if role in f: roles.setdefault(role, img)
    for role, img in roles.items():
        img.colorspace_settings.name = 'Non-Color'
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = img
        if role == 'normal':
            nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
        else:
            nt.links.new(n.outputs['Color'], bsdf.inputs['Metallic' if role == 'metal' else 'Roughness'])
    print('material', m.name, 'maps:', sorted(l.to_socket.name for l in nt.links if l.to_node in (bsdf,) or l.to_node.type == 'NORMAL_MAP'))

# Real-world scale, transforms applied (FBX arrives in centimetres, rotated 90 degrees). Each object is applied on
# its own, unparented: applying parent and child together lays the figure on its back.
bpy.context.view_layer.update()
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
s = HEIGHT / (max(zs) - min(zs))
for o in (body, rig):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
    if o.parent: bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    o.matrix_world = Matrix.Scale(s, 4) @ o.matrix_world; bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.parent = rig
bpy.context.view_layer.update()
hips_z, head_z = (rig.data.bones[n].head_local.z for n in ('mixamorig:Hips', 'mixamorig:Head'))
zs = [v.co.z for v in body.data.vertices]
print(f'standing {min(zs):.3f}..{max(zs):.3f} m, hips {hips_z:.3f}, head {head_z:.3f}')
assert head_z > hips_z > 0.3 and abs(max(zs) - min(zs) - HEIGHT) < 0.01, 'the rig is not upright at the requested height'

# Meshy bone names; finger weights folded into the hands and the finger bones removed.
for b in rig.data.bones:
    short = b.name.split(':')[-1]; b.name = MIXAMO_TO_MESHY.get(short, short)   # renames the vertex groups too
fingers = [b.name for b in rig.data.bones if re.match(r'(Left|Right)Hand(Thumb|Index|Middle|Ring|Pinky)\d', b.name)]
for fname in fingers:
    vg = body.vertex_groups.get(fname)
    if vg:
        hand = body.vertex_groups[fname.split('Hand')[0] + 'Hand']
        for v in body.data.vertices:
            for g in v.groups:
                if g.group == vg.index and g.weight > 0: hand.add([v.index], g.weight, 'ADD')
        body.vertex_groups.remove(vg)
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
for fname in fingers: rig.data.edit_bones.remove(rig.data.edit_bones[fname])
bpy.ops.object.mode_set(mode='OBJECT')
missing = [n for n in TORSO + LIMBS if n not in rig.data.bones]
assert not missing, f'bones missing after renaming: {missing}'
print('target bones', [b.name for b in rig.data.bones])


def forward(arm):
    """Which way a rig faces, from its left foot: heel to toe, flattened."""
    m = arm.matrix_world; d = (m @ arm.data.bones['LeftToeBase'].head_local) - (m @ arm.data.bones['LeftFoot'].head_local)
    d.z = 0; return d.normalized()


for pb in rig.pose.bones: pb.rotation_mode = 'QUATERNION'
arm_mod = next(m for m in body.modifiers if m.type == 'ARMATURE'); arm_mod.show_viewport = False   # faster frame_set
T = rig.data.bones
t_rest = {b.name: b.matrix_local.copy() for b in T}
t_rel = {b.name: (b.parent.matrix_local.inverted() @ b.matrix_local if b.parent else b.matrix_local.copy()) for b in T}
order = []
def walk(b):
    order.append(b.name)
    for c in b.children: walk(c)
for b in T:
    if not b.parent: walk(b)
done = set()
rig.animation_data_create()

for path in sources:
    before_obj, before_act = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new_obj = [o for o in bpy.data.objects if o not in before_obj]
    new_act = [a for a in bpy.data.actions if a not in before_act]
    src = next(o for o in new_obj if o.type == 'ARMATURE')
    for o in new_obj:
        if o.type == 'MESH': bpy.data.objects.remove(o)
    for t in list(src.animation_data.nla_tracks): src.animation_data.nla_tracks.remove(t)
    # Face the source the same way as the target (turn it about the world origin).
    pivot = bpy.data.objects.new('pivot', None); bpy.context.scene.collection.objects.link(pivot)
    top = src
    while top.parent: top = top.parent
    top.parent = pivot; bpy.context.view_layer.update()
    fs, ft = forward(src), forward(rig)
    pivot.rotation_euler.z = math.atan2(fs.x * ft.y - fs.y * ft.x, fs.dot(ft)); bpy.context.view_layer.update()
    S = src.data.bones; sw = src.matrix_world
    s_rest = {n: (sw @ S[n].matrix_local).to_3x3().normalized() for n in TORSO + LIMBS}
    align = {n: Matrix.Identity(3) for n in TORSO}
    for n in LIMBS:
        align[n] = t_rest[n].to_3x3().col[1].rotation_difference(s_rest[n].col[1]).to_matrix()
    s_hips0 = sw @ S['Hips'].head_local; t_hips0 = t_rest['Hips'].translation.copy()
    k = t_hips0.z / s_hips0.z
    for act in new_act:
        name = re.sub(r'\.\d{3}$', '', act.name)
        if name in done: continue
        done.add(name)
        src.animation_data.action = act
        if act.slots: src.animation_data.action_slot = act.slots[0]
        tgt = bpy.data.actions.new(name); tgt.use_fake_user = True; rig.animation_data.action = tgt
        f0, f1 = (int(round(x)) for x in act.frame_range)
        prev = {}
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            P = {}
            for n in order:
                parent = T[n].parent
                base = (P[parent.name] @ t_rel[n]) if parent else t_rel[n]
                if n in align:
                    d = (sw @ src.pose.bones[n].matrix).to_3x3().normalized() @ s_rest[n].transposed()   # world delta
                    R = d @ align[n] @ t_rest[n].to_3x3()
                    if parent:
                        basis = (base.to_3x3().normalized().inverted() @ R).to_4x4()
                    else:
                        head = t_hips0 + ((sw @ src.pose.bones[n].head) - s_hips0) * k
                        basis = t_rest[n].inverted() @ (Matrix.Translation(head) @ R.to_4x4())
                    pb = rig.pose.bones[n]
                    loc, q, _ = basis.decompose()
                    if n in prev and prev[n].dot(q) < 0: q.negate()
                    prev[n] = q
                    pb.rotation_quaternion = q; pb.keyframe_insert('rotation_quaternion', frame=f)
                    if not parent: pb.location = loc; pb.keyframe_insert('location', frame=f)
                    P[n] = base @ basis
                else:
                    P[n] = base
        print(f'  {name}: {f1 - f0 + 1} frames from {path.split("/")[-4]}', flush=True)
    for a in new_act: bpy.data.actions.remove(a)
    for o in [o for o in bpy.data.objects if o not in before_obj]: bpy.data.objects.remove(o)
    for a in bpy.data.actions: a.name = re.sub(r'\.\d{3}$', '', a.name)   # the source clips held the names until now

rig.animation_data.action = None
for pb in rig.pose.bones: pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
arm_mod.show_viewport = True
bpy.context.scene.frame_set(0)
print('actions', sorted(done))
bpy.ops.wm.save_as_mainfile(filepath=out)
print('DONE')
