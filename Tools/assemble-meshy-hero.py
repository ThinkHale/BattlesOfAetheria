# Blender: assemble a game-ready hero from Meshy outputs (rigged + animated character, separate cape and gear).
#   blender -b --factory-startup -P Tools/assemble-meshy-hero.py -- meshy_dir out.blend [Name] [weapon_len_m] [skirt]
# skirt (default 0.65): how much of a flared skirt or coat follows the pelvis instead of the thighs; 0 for a short
# kilt over bare, muscular thighs (their skin sits far enough from the bone to be mistaken for skirt).
# meshy_dir holds: anims/batch*_result_animation_glb_url.glb (rigged mesh + clips), or instead rigged.blend from
# Tools/retarget-mixamo-hero.py; and optional props, each <slot>/model_urls_glb.glb: gladius (any sword), spear,
# staff, fan, sistrum, crossbow, bow, quiver, shield, sheath, cape. The rig has no finger bones, so fists are shaped
# into the rest mesh. An optional meshy_dir/props.json overrides each slot's size and grip, e.g.
#   {"spear": {"length": 2.0, "grip": 0.3}, "staff": {"length": 1.65, "grip": 0.42, "hand": "Right"},
#    "shield": {"height": 0.8}, "sheath": {"length": 0.4}, "skirt": 0.9, "robe": true}
# "oriented": true (set for Tools/build-weapon.py props) skips the guess at which end is the tip.
import bpy, bmesh, sys, glob, json, math, numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
D, out = argv[:2]
NAME = argv[2] if len(argv) > 2 else 'Gaius'
SHIELD_H, GLADIUS_LEN = 0.85, float(argv[3]) if len(argv) > 3 else 0.66
SHEATH_LEN = GLADIUS_LEN * 0.85
SPEAR_LEN, SPEAR_GRIP = (float(argv[3]) if len(argv) > 3 else 1.7), 0.3   # held 30% of the way up from the butt
BOW_LEN = 1.25
import os
has = lambda n: os.path.exists(f'{D}/{n}/model_urls_glb.glb')
HAS_SHIELD = has('shield')
CFG = json.load(open(f'{D}/props.json')) if os.path.exists(f'{D}/props.json') else {}
SKIRT_PELVIS = float(argv[4]) if len(argv) > 4 else CFG.get('skirt', 0.65)
SHIELD_H = CFG.get('shield', {}).get('height', SHIELD_H)
SHEATH_LEN = CFG.get('sheath', {}).get('length', SHEATH_LEN)
BOW_LEN = CFG.get('bow', {}).get('length', BOW_LEN)

bpy.ops.wm.read_factory_settings(use_empty=True)
batches = sorted(glob.glob(f'{D}/anims/batch*_result_animation_glb_url.glb'))
if batches: bpy.ops.import_scene.gltf(filepath=batches[0])
else: bpy.ops.wm.open_mainfile(filepath=f'{D}/rigged.blend')      # a Mixamo rig already carrying retargeted clips
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.vertices) > 1000)
rig.name, body.name = f'{NAME}_rig', NAME
for o in [o for o in bpy.context.scene.objects if o.type == 'MESH' and o is not body]: bpy.data.objects.remove(o)   # helper sphere
for path in batches[1:]:
    before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=path)
    for o in [o for o in bpy.data.objects if o not in before]: bpy.data.objects.remove(o)
for a in bpy.data.actions: a.use_fake_user = True
print('actions', sorted(a.name for a in bpy.data.actions))
# Meshy's rigged GLB faces +Y in Blender; turn him to face -Y like every other hero (screen-right in side renders).
# Every hero faces -Y (screen-right in the side-on renders). Read his facing from his feet: toes point forward.
root = bpy.data.objects.new(f'{NAME}_root', None); bpy.context.scene.collection.objects.link(root); rig.parent = root
bpy.context.view_layer.update()
toe = rig.matrix_world @ rig.data.bones['LeftToeBase'].head_local; heel = rig.matrix_world @ rig.data.bones['LeftFoot'].head_local
if (toe - heel).y > 0: root.rotation_euler = (0, 0, math.pi)
bpy.context.view_layer.update()
print('facing fixed: toes now point', 'forward (-Y)' if ((rig.matrix_world @ rig.data.bones['LeftToeBase'].head_local) - (rig.matrix_world @ rig.data.bones['LeftFoot'].head_local)).y < 0 else 'BACKWARD')

rig.data.pose_position = 'REST'; bpy.context.view_layer.update()
mw = body.matrix_world; inv = mw.inverted()
co = np.array([tuple(mw @ v.co) for v in body.data.vertices])
gi = {g.name: g.index for g in body.vertex_groups}
dom = np.array([max(v.groups, key=lambda g: g.weight).group if len(v.groups) else -1 for v in body.data.vertices])
bone_head = lambda n: np.array(rig.matrix_world @ rig.data.bones[n].head_local)


# ---------------- hands: frame (u fingers, t palm, w thumb side) and baked fists ----------------
def hand_frame(side):
    hv = co[dom == gi[side + 'Hand']]; wrist = bone_head(side + 'Hand')
    c = hv.mean(0); u = c - wrist; u /= np.linalg.norm(u)
    d = hv - wrist; t = np.linalg.svd(d - d.mean(0))[2][2]; t = t - u * t.dot(u); t /= np.linalg.norm(t)
    w = np.cross(u, t)
    # Thumb side: across the palm (0.15-0.5 of the hand), the thumb sticks out further on its side.
    du, dw, dt = d @ u, d @ w, d @ t; L = du.max(); mid = (du > 0.15 * L) & (du < 0.5 * L)
    if -dw[mid].min() > dw[mid].max(): w = -w; dw = -dw
    # Palm side: the thumb sits toward the palm.
    th = mid & (dw > np.percentile(dw[du > 0.75 * L], 98) + 0.004)
    if th.any() and np.median(dt[th]) < np.median(dt): t = -t
    return wrist, u, t, w


def bake_fist(side):
    wrist, u, t, w = hand_frame(side)
    idx = np.where((dom == gi[side + 'Hand']))[0]
    p = co[idx] - wrist; du, dt, dw = p @ u, p @ t, p @ w; L = du.max()
    xs = np.arange(0.2 * L, L, 0.004)
    width = np.array([np.ptp(dw[np.abs(du - x) < 0.004]) if np.sum(np.abs(du - x) < 0.004) > 2 else 0 for x in xs])
    wf = np.median(width[xs > 0.75 * L])
    cand = np.where((width <= wf + 0.02) & (width > 0) & (xs > 0.4 * L))[0]
    knuckle = xs[cand[0]] if len(cand) else 0.55 * L
    fing = du > knuckle
    fw0 = np.percentile(dw[fing], 98)
    thumb = (du > 0.12 * L) & (du <= knuckle + 0.01) & (dw > fw0 + 0.004)
    fing &= ~thumb
    tc = float(np.median(dt[fing]))                                   # finger mid-plane (palm direction coordinate)
    Lf = L - knuckle; A = math.radians(250); R = Lf / A
    nu, nt, nw = du.copy(), dt.copy(), dw.copy()
    for k in np.where(fing)[0]:
        phi = min((du[k] - knuckle) / R, A); h = -(dt[k] - tc)       # height above the finger mid-plane, away from palm
        cu = knuckle + R * math.sin(phi); ct = tc + R * (1 - math.cos(phi))
        nu[k] = cu - h * math.sin(phi); nt[k] = ct - h * math.cos(phi)
    if thumb.any():                                                    # fold the thumb across the curled fingers
        b0 = np.array([0.15 * L, tc, fw0]); th = math.radians(75)
        for k in np.where(thumb)[0]:
            v = np.array([du[k], dt[k], dw[k]]) - b0
            # rotate about u: thumb side (w) toward the palm (t)
            v = np.array([v[0], v[1] * math.cos(th) + v[2] * math.sin(th), -v[1] * math.sin(th) + v[2] * math.cos(th)])
            nu[k], nt[k], nw[k] = v + b0
    newp = wrist + np.outer(nu, u) + np.outer(nt, t) + np.outer(nw, w)
    for j, k in enumerate(idx): body.data.vertices[k].co = inv @ Vector(newp[j])
    grip = wrist + u * (knuckle + 0.3 * R) + t * (tc + R) + w * float(np.median(dw[fing]))
    print(side, 'fist: knuckle %.3f of %.3f, fingers %d, thumb %d' % (knuckle, L, fing.sum(), thumb.sum()))
    return Vector(grip), Vector(u), Vector(t), Vector(w)


grips = {s: bake_fist(s) for s in ('Left', 'Right')}
body.data.update()


# ---------------- props ----------------
def load(name):
    before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=f'{D}/{name}/model_urls_glb.glb')
    new = [o for o in bpy.data.objects if o not in before]; ob = next(o for o in new if o.type == 'MESH')
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM'); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o is not ob: bpy.data.objects.remove(o)
    ob.name = name; return ob


def pts(ob): return np.array([tuple(ob.matrix_world @ v.co) for v in ob.data.vertices])


def frame(x, y, z, o):
    m = Matrix.Identity(4)
    for i, v in enumerate((x, y, z)): m.col[i][:3] = v.normalized()
    m.col[3][:3] = o; return m


def orient_long(ob, tip_to_plus_x):
    """Rotate a long prop so its length runs along X (tip, the thinner end, at +X or -X) and its width along Z."""
    p = pts(ob); ext = np.ptp(p, 0); ax = int(np.argmax(ext)); rest = [i for i in range(3) if i != ax]
    wid = rest[int(np.argmax(ext[rest]))]; thk = [i for i in rest if i != wid][0]
    lo, hi = p[:, ax].min(), p[:, ax].max(); L = hi - lo
    end_area = lambda sel: np.ptp(p[sel][:, wid]) * np.ptp(p[sel][:, thk]) if sel.sum() > 3 else 0
    tip_hi = end_area(p[:, ax] > hi - 0.08 * L) < end_area(p[:, ax] < lo + 0.08 * L)
    M = np.zeros((3, 3)); sign = 1 if tip_hi == tip_to_plus_x else -1
    M[0, ax] = sign; M[2, wid] = 1; M[1] = np.cross(M[2], M[0])
    ob.data.transform(Matrix(M.tolist()).to_4x4())


def attach(ob, bone, world):
    ob.parent = rig; ob.parent_type = 'BONE'; ob.parent_bone = bone; bpy.context.view_layer.update(); ob.matrix_world = world


def fit_in_hand(bone, clips, targets):
    """One fixed rotation (prop axes -> hand-bone axes) that best matches, over sampled frames of the clips, each
    prop axis to a world direction (Wahba's problem, solved by SVD). targets(frame) -> [(prop_axis, world_dir, weight)].
    Returns the prop axes in the rest pose (world), as a 3x3 numpy array."""
    rig.data.pose_position = 'POSE'
    bone_rest = (rig.matrix_world.to_3x3() @ rig.data.bones[bone].matrix_local.to_3x3()).normalized()
    A, Bv = [], []
    for act_name, wgt in clips:
        if act_name not in bpy.data.actions: continue
        act = bpy.data.actions[act_name]; rig.animation_data.action = act; rig.animation_data.action_slot = act.slots[0]
        f0, f1 = map(int, act.frame_range)
        for f in range(f0, f1 + 1, max(1, (f1 - f0) // 10)):
            bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
            mi = (rig.matrix_world.to_3x3() @ rig.pose.bones[bone].matrix.to_3x3()).normalized().inverted()
            for ax, wd, k_ in targets():
                A.append(np.array(ax) * wgt * k_); Bv.append(np.array(mi @ Vector(wd)) * wgt * k_)
    Hm = np.array(Bv).T @ np.array(A); U_, _, Vt = np.linalg.svd(Hm)
    Rl = U_ @ np.diag([1, 1, np.sign(np.linalg.det(U_ @ Vt))]) @ Vt
    rig.animation_data.action = None; rig.data.pose_position = 'REST'; bpy.context.view_layer.update()
    return np.array(bone_rest) @ Rl


HELD = (('gladius', GLADIUS_LEN, 0.13, 'Right'), ('spear', SPEAR_LEN, SPEAR_GRIP, 'Right'), ('staff', 1.65, 0.42, 'Right'),
        ('fan', 0.32, 0.0, 'Right'), ('sistrum', 0.36, 0.25, 'Left'))
for kind, length, grip, hand in HELD:
    if not has(kind): continue
    cf = CFG.get(kind, {}); length, grip, hand = cf.get('length', length), cf.get('grip', grip), cf.get('hand', hand)
    # Tip +X, edges along Z, pommel (butt) at -X; the grip centre is ~13% in from a sword's pommel end.
    g = load(kind)
    if not cf.get('oriented'): orient_long(g, True)
    gp = pts(g); L = gp[:, 0].max() - min(0.0, gp[:, 0].min()) if cf.get('oriented') else np.ptp(gp[:, 0])
    x0 = min(0.0, gp[:, 0].min()) if cf.get('oriented') else gp[:, 0].min()
    gx = x0 + grip * L; hilt = gp[np.abs(gp[:, 0] - gx) < 0.05 * L]       # centre on the grip (a khopesh curves)
    if not len(hilt): hilt = gp[np.argsort(np.abs(gp[:, 0] - gx))[:20]]
    g.data.transform(Matrix.Translation((-gx, -np.median(hilt[:, 1]), -np.median(hilt[:, 2]))))
    g.data.transform(Matrix.Scale(length / L, 4))
    c, u, t, w = grips[hand]
    if cf.get('upright'):
        # A staff or standard: one fixed grip that keeps it upright with its decorated face (XZ) toward the side
        # camera over the stance and walk clips; attacks then swing it from there.
        Rw = fit_in_hand(f'{hand}Hand', cf['upright'], lambda: [((1, 0, 0), (0, 0, 1), 1.0), ((0, 1, 0), (-1, 0, 0), 0.4)])
        attach(g, f'{hand}Hand', frame(Vector(Rw[:, 0]), Vector(Rw[:, 1]), Vector(Rw[:, 2]), c))
    else:
        attach(g, f'{hand}Hand', frame(w, u.cross(w), u, c))     # out of the thumb side, edges along the fingers
    print(kind, 'in the', hand.lower(), 'hand, %.2f m' % length, '(fitted upright)' if cf.get('upright') else '')


if has('crossbow'):
    # Crossbow (Tools/build-weapon.py: stock along +X, top +Z): the left fist holds the fore-stock and the bow-aiming
    # clips drive it, so point it along the aiming arm (spine to left hand) with its top up; the butt comes back to the
    # right shoulder where the draw hand sits.
    cf = CFG.get('crossbow', {}); length, grip = cf.get('length', 0.85), cf.get('grip', 0.62)
    x_ = load('crossbow'); xp = pts(x_); L = xp[:, 0].max()
    x_.data.transform(Matrix.Translation((-grip * L, 0, 0))); x_.data.transform(Matrix.Scale(length / L, 4))
    def aim_targets():
        d = (rig.matrix_world @ rig.pose.bones['LeftHand'].head) - (rig.matrix_world @ rig.pose.bones['Spine'].head)
        return [((1, 0, 0), tuple(d.normalized()), 1.0), ((0, 0, 1), (0, 0, 1), 0.6)]
    Rw = fit_in_hand('LeftHand', [(n, 1) for n in ('Archery_Aim_with_Lateral_Scan', 'Walk_Forward_with_Bow_Aimed', 'Archery_Shot',
                                                  'Archery_Shot_1')], aim_targets)
    c, u, t, w = grips['Left']
    attach(x_, 'LeftHand', frame(Vector(Rw[:, 0]), Vector(Rw[:, 1]), Vector(Rw[:, 2]), c))
    print('crossbow in the left hand, %.2f m' % length)

if HAS_SHIELD:
    # Scutum: face toward -Y, tall along Z. Upright on the left fist, face out from the back of the hand.
    s = load('shield'); sp = pts(s); H = np.ptp(sp[:, 2])
    s.data.transform(Matrix.Translation((-np.median(sp[:, 0]), -sp[:, 1].max(), -(sp[:, 2].min() + 0.5 * H))))   # back face at the origin
    s.data.transform(Matrix.Scale(SHIELD_H / H, 4))
    c, u, t, w = grips['Left']
    # Orient the scutum from the clips: find the one fixed rotation in hand-bone space that best keeps its face toward
    # the opponent (-Y) and its height upright over the guard, walk and parry frames (Wahba's problem, solved by SVD).
    rig.data.pose_position = 'POSE'
    bone_rest = (rig.matrix_world.to_3x3() @ rig.data.bones['LeftHand'].matrix_local.to_3x3()).normalized()
    A, Bv = [], []
    for act_name, wgt in (('Combat_Stance', 3), ('Walk_Fight_Forward', 2), ('Walk_Backward_with_Sword_Shield', 2), ('Sword_Parry', 1)):
        act = bpy.data.actions[act_name]; rig.animation_data.action = act; rig.animation_data.action_slot = act.slots[0]
        f0, f1 = map(int, act.frame_range)
        for f in range(f0, f1 + 1, max(1, (f1 - f0) // 8)):
            bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
            mi = (rig.matrix_world.to_3x3() @ rig.pose.bones['LeftHand'].matrix.to_3x3()).normalized().inverted()
            for model_axis, world_dir, k_ in (((0, -1, 0), (0, -1, 0), 1.0), ((0, 0, 1), (0, 0, 1), 0.7)):
                A.append(np.array(model_axis) * wgt * k_); Bv.append(np.array(mi @ Vector(world_dir)) * wgt * k_)
    Hm = np.array(Bv).T @ np.array(A); U_, _, Vt = np.linalg.svd(Hm)
    Rl = U_ @ np.diag([1, 1, np.sign(np.linalg.det(U_ @ Vt))]) @ Vt     # shield axes -> hand-bone axes
    rig.animation_data.action = None; rig.data.pose_position = 'REST'; bpy.context.view_layer.update()
    Rw = np.array(bone_rest) @ Rl                                        # shield axes in the rest pose (world)
    width, back_dir, tall = (Vector(Rw[:, i]) for i in range(3))
    front = -back_dir
    attach(s, 'LeftHand', frame(width, -front, tall, c + front * 0.045))

if has('sheath'):
    # Sheath: generated tip -X, mouth +X, suspension ring +Z. Hangs on his left hip (right-handed draw), angled back.
    sh = load('sheath')
    if not CFG.get('sheath', {}).get('oriented'): orient_long(sh, False)
    hp = pts(sh); L = np.ptp(hp[:, 0])
    sh.data.transform(Matrix.Translation((-hp[:, 0].max(), -np.median(hp[:, 1]), -np.median(hp[:, 2]))))
    sh.data.transform(Matrix.Scale(SHEATH_LEN / L, 4))
    hips_z = bone_head('Hips')[2]; belt_z = hips_z + 0.06
    # Torso only: in an A-pose the hands hang at belt height, so keep vertices driven by the hips and spine.
    torso_g = [gi[n] for n in ('Hips', 'Spine', 'Spine01', 'Spine02') if n in gi]
    band = co[(np.abs(co[:, 2] - belt_z) < 0.03) & np.isin(dom, torso_g)]
    mouth = Vector((band[:, 0].max() + 0.035, float(np.median(band[:, 1])) + 0.04, belt_z))
    tip = Vector((0.06, 0.18, -1)).normalized()
    x_ = -tip; z_ = Vector((1, 0, 0)); y_ = z_.cross(x_)
    attach(sh, 'Hips', frame(x_, y_, x_.cross(y_), mouth))

if has('cape'):
    # ---------------- cape: centred on the shoulders, upper part draped onto the back ----------------
    k = load('cape'); k.data.transform(Matrix.Rotation(math.pi, 4, 'Z'))   # generated facing the other way
    bpy.context.view_layer.objects.active = k
    bm_ = bmesh.new(); bm_.from_mesh(k.data); bmesh.ops.remove_doubles(bm_, verts=bm_.verts, dist=1e-4); bm_.to_mesh(k.data); bm_.free()   # Meshy splits vertices at UV seams; cloth needs one connected sheet
    dec = k.modifiers.new('dec', 'DECIMATE'); dec.ratio = 5000 / len(k.data.polygons); bpy.ops.object.modifier_apply(modifier='dec')   # light enough to simulate
    kp = pts(k)
    neck_z = bone_head('neck')[2]
    shoulders = co[(np.abs(co[:, 2] - (neck_z - 0.06)) < 0.03) & (np.abs(co[:, 0]) < 0.35)]
    top = kp[kp[:, 2] > kp[:, 2].max() - 0.15 * np.ptp(kp[:, 2])]
    sc_ = np.ptp(shoulders[:, 0]) * 1.12 / np.ptp(top[:, 0])
    k.data.transform(Matrix.Translation((-np.median(top[:, 0]), -np.median(top[:, 1]), -kp[:, 2].max())))
    k.data.transform(Matrix.Scale(sc_, 4))
    k.data.transform(Matrix.Translation((0, float(np.median(shoulders[:, 1])) + 0.02, neck_z + 0.07)))
    kp = pts(k); chest_z = neck_z - 0.25
    # Open the cloak at the front: drop the panel hanging in front of the torso below the shoulders, so the armour shows.
    torso_front = co[(co[:, 2] > chest_z - 0.35) & (co[:, 2] < neck_z - 0.10) & (np.abs(co[:, 0]) < 0.18)]
    front_y = float(np.percentile(torso_front[:, 1], 30))
    bm_ = bmesh.new(); bm_.from_mesh(k.data)
    drop = [f for f in bm_.faces if (lambda c: c.y < front_y and c.z < neck_z - 0.12 and abs(c.x) < 0.30)(f.calc_center_median())]
    bmesh.ops.delete(bm_, geom=drop, context='FACES'); bmesh.ops.delete(bm_, geom=[v for v in bm_.verts if not v.link_faces], context='VERTS')
    bm_.to_mesh(k.data); bm_.free(); print('cloak front faces removed:', len(drop))
    kp = pts(k)
    vg = k.vertex_groups.new(name='drape')
    for i, p in enumerate(kp):
        wgt = float(np.clip((p[2] - (chest_z - 0.25)) / 0.30, 0, 1))
        if wgt > 0: vg.add([i], wgt, 'REPLACE')
    sw = k.modifiers.new('drape', 'SHRINKWRAP'); sw.target = body; sw.wrap_method = 'NEAREST_SURFACEPOINT'
    sw.wrap_mode = 'OUTSIDE_SURFACE'; sw.offset = 0.02; sw.vertex_group = 'drape'
    bpy.context.view_layer.objects.active = k; bpy.ops.object.modifier_apply(modifier='drape')
    pin = k.vertex_groups.new(name='pin')                          # cloth simulation pins the shoulders, frees the hem
    for i, p in enumerate(pts(k)): pin.add([i], float(np.clip((p[2] - (chest_z - 0.05)) / 0.15, 0, 1)), 'REPLACE')
    # Skin it: copy the body's weights, but never the legs (it hangs from the shoulders).
    for b in rig.data.bones: k.vertex_groups.new(name=b.name)
    dt = k.modifiers.new('w', 'DATA_TRANSFER'); dt.object = body; dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}; dt.vert_mapping = 'POLYINTERP_NEAREST'; dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
    bpy.ops.object.modifier_apply(modifier='w')
    # A cloak hangs from the shoulders: arm weights go to the collarbones, leg weights to the spine; the cloth
    # simulation moves everything below the pin line.
    remap = {f'{s_}{b_}': f'{s_}Shoulder' for s_ in ('Left', 'Right') for b_ in ('Arm', 'ForeArm', 'Hand')}
    remap.update({n: 'Spine02' for n in ('Hips', 'LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg', 'LeftFoot', 'RightFoot', 'LeftToeBase', 'RightToeBase')})
    idx_name = {vg.index: vg.name for vg in k.vertex_groups}
    for v in k.data.vertices:
        moves = [(gg.group, gg.weight) for gg in v.groups if idx_name[gg.group] in remap and gg.weight > 0]
        for gidx, wv in moves:
            k.vertex_groups[gidx].remove([v.index]); k.vertex_groups[remap[idx_name[gidx]]].add([v.index], wv, 'ADD')
    k.parent = rig; k.matrix_parent_inverse = rig.matrix_world.inverted(); am = k.modifiers.new('rig', 'ARMATURE'); am.object = rig
    cl = k.modifiers.new('cloth', 'CLOTH'); cs = cl.settings
    cs.vertex_group_mass = 'pin'; cs.quality = 6; cs.mass = 0.4; cs.tension_stiffness = 25; cs.compression_stiffness = 25
    cs.bending_stiffness = 3.0; cs.air_damping = 4.0; cs.pin_stiffness = 1.0
    cl.collision_settings.use_collision = True; cl.collision_settings.distance_min = 0.012; cl.collision_settings.use_self_collision = False
    # Collide against a light copy of the body that follows the rig (hidden from renders), not the 56k-vertex mesh.
    proxy = body.copy(); proxy.data = body.data.copy(); proxy.name = f'{NAME}_collider'; bpy.context.scene.collection.objects.link(proxy)
    for m in list(proxy.modifiers):
        if m.type != 'ARMATURE': proxy.modifiers.remove(m)
    bpy.context.view_layer.objects.active = proxy
    dm = proxy.modifiers.new('dec', 'DECIMATE'); dm.ratio = 6000 / len(proxy.data.polygons)
    bpy.ops.object.modifier_move_to_index(modifier='dec', index=0); bpy.ops.object.modifier_apply(modifier='dec')
    proxy.modifiers.new('collision', 'COLLISION'); proxy.collision.thickness_outer = 0.015; proxy.collision.cloth_friction = 2
    proxy.hide_render = True; proxy.display_type = 'WIRE'


# ---------------- archer: bow in the left fist, quiver on the back ----------------
props = []
if has('bow'):
    b = load('bow'); orient_long(b, True); bp = pts(b)
    b.data.transform(Matrix.Translation((-np.median(bp[:, 0]), -np.median(bp[:, 1]), -np.median(bp[:, 2]))))
    bp = pts(b); Lb = np.ptp(bp[:, 0]); b.data.transform(Matrix.Scale(BOW_LEN / Lb, 4)); bp = pts(b)
    # The string runs between the tips; the limbs bow away from it. String side = where the tips sit in Z.
    tips_z = bp[np.abs(bp[:, 0]) > 0.4 * np.ptp(bp[:, 0]), 2].mean(); grip_z = bp[np.abs(bp[:, 0]) < 0.05 * np.ptp(bp[:, 0]), 2].mean()
    string_side = 1.0 if tips_z > grip_z else -1.0
    b.data.transform(Matrix.Translation((0, 0, -grip_z)))          # grip on the origin
    c, u, t, w = grips['Left']
    # Fit one fixed rotation in hand space over the aiming clips: bow upright (+X up), string toward her (+Y, the
    # enemy is at -Y) — the same least-squares fit as the scutum.
    rig.data.pose_position = 'POSE'
    bone_rest = (rig.matrix_world.to_3x3() @ rig.data.bones['LeftHand'].matrix_local.to_3x3()).normalized()
    A, Bv = [], []
    aim = [n for n in ('Archery_Aim_with_Lateral_Scan', 'Walk_Forward_with_Bow_Aimed', 'Archery_Shot', 'Hit_Reaction_with_Bow') if n in bpy.data.actions]
    for act_name in aim:
        act = bpy.data.actions[act_name]; rig.animation_data.action = act; rig.animation_data.action_slot = act.slots[0]
        f0, f1 = map(int, act.frame_range)
        for f in range(f0, f1 + 1, max(1, (f1 - f0) // 10)):
            bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
            mi = (rig.matrix_world.to_3x3() @ rig.pose.bones['LeftHand'].matrix.to_3x3()).normalized().inverted()
            for ma, wd, k_ in (((1, 0, 0), (0, 0, 1), 1.0), ((0, 0, string_side), (0, 1, 0), 0.8)):
                A.append(np.array(ma) * k_); Bv.append(np.array(mi @ Vector(wd)) * k_)
    Hm = np.array(Bv).T @ np.array(A); U_, _, Vt = np.linalg.svd(Hm)
    Rl = U_ @ np.diag([1, 1, np.sign(np.linalg.det(U_ @ Vt))]) @ Vt
    rig.animation_data.action = None; rig.data.pose_position = 'REST'; bpy.context.view_layer.update()
    Rw = np.array(bone_rest) @ Rl
    attach(b, 'LeftHand', frame(Vector(Rw[:, 0]), Vector(Rw[:, 1]), Vector(Rw[:, 2]), c))
    props.append(b); print('bow attached, string side', string_side)
if has('quiver'):
    q = load('quiver'); orient_long(q, True); qp = pts(q); Lq = np.ptp(qp[:, 0])
    q.data.transform(Matrix.Translation((-qp[:, 0].min(), -np.median(qp[:, 1]), -np.median(qp[:, 2]))))   # mouth at origin
    q.data.transform(Matrix.Scale(CFG.get('quiver', {}).get('length', 0.62) / Lq, 4))
    neck_z = bone_head('neck')[2]
    back = co[(np.abs(co[:, 2] - (neck_z - 0.2)) < 0.04) & (np.abs(co[:, 0]) < 0.15)]
    mouth = Vector((-0.10, float(back[:, 1].max()) + 0.05, neck_z - 0.02))     # behind the right shoulder (her right is -X)
    down = Vector((0.35, 0.05, -1)).normalized()                                  # slung diagonally across the back
    face = Vector((0, 1, 0)); y_ = (face - down * face.dot(down)).normalized()
    attach(q, 'Spine02', frame(down, y_, down.cross(y_), mouth))
    props.append(q)

# ---------------- skirt: hem and apron follow the pelvis more than the thighs ----------------
def seg(p, a, b):
    ab = b - a; tt = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1); return np.linalg.norm(p - (a + tt[:, None] * ab), axis=1)


knee_z = bone_head('LeftLeg')[2]; hips_z = bone_head('Hips')[2]
ROBE = CFG.get('robe')
if ROBE:
    # A long robe: below the waist, blend from the pelvis (at the belt) to the legs (at the hem), each side of the robe
    # following its own leg and the middle following both. A wide stance then flares the robe like a bell, where the
    # skirt pass below (pelvis above the knee, shins below) folds it into a shelf. Feet keep their own weights.
    hem_z, follow = ROBE.get('hem', 0.08), ROBE.get('follow', 0.65)
    leg_names = [f'{s_}{b_}' for s_ in ('Left', 'Right') for b_ in ('UpLeg', 'Leg')]
    lower = {gi[n] for n in ['Hips', 'Spine02'] + leg_names if n in gi}
    for n in leg_names + ['Hips']:
        if n not in gi: body.vertex_groups.new(name=n); gi[n] = body.vertex_groups[n].index
    belt_z = hips_z + 0.04
    # A floor-length gown also covers the foot bones: take foot-weighted vertices too, except the feet themselves
    # (within 7 cm of the heel-to-toe line).
    feet = {gi[n] for n in ('LeftFoot', 'RightFoot', 'LeftToeBase', 'RightToeBase') if n in gi}
    foot_d = np.minimum(*[seg(co, bone_head(s_ + 'Foot'), bone_head(s_ + 'ToeBase')) for s_ in ('Left', 'Right')])
    gown = np.isin(dom, list(lower)) | (np.isin(dom, list(feet)) & (foot_d > 0.07) & (co[:, 2] > 0.02))
    sel = np.where((co[:, 2] > hem_z) & (co[:, 2] < belt_z) & gown)[0]
    cx = float(np.median(co[sel, 0])) if len(sel) else 0.0
    half = 0.5 * abs(bone_head('LeftUpLeg')[0] - bone_head('RightUpLeg')[0]) + 0.02
    for vi in sel:
        x, z = co[vi, 0] - cx, co[vi, 2]
        t = np.clip((belt_z - z) / (belt_z - hem_z), 0, 1)                   # 0 at the belt, 1 at the hem
        legw = follow * t ** 0.8
        sl = np.clip(0.5 + 0.5 * x / half, 0, 1); sl = sl * sl * (3 - 2 * sl)   # +X is her left
        up = np.clip((z - (knee_z - 0.08)) / 0.16, 0, 1)                      # thigh above the knee, shin below
        wts = {'Hips': 1 - legw}
        for side, share in (('Left', sl), ('Right', 1 - sl)):
            wts[side + 'UpLeg'] = legw * share * up; wts[side + 'Leg'] = legw * share * (1 - up)
        v = body.data.vertices[int(vi)]
        for g_ in list(v.groups): body.vertex_groups[g_.group].remove([int(vi)])
        for n, wv in wts.items():
            if wv > 1e-4: body.vertex_groups[n].add([int(vi)], float(wv), 'REPLACE')
    print('robe vertices reweighted: %d (hem %.2f m, follows the legs %.0f%% at the hem)' % (len(sel), hem_z, 100 * follow))
    SKIRT_PELVIS = 0.0
dist = np.minimum(*[seg(co, bone_head(s + 'UpLeg'), bone_head(s + 'Leg')) for s in ('Left', 'Right')])
zone = (co[:, 2] > knee_z) & (co[:, 2] < hips_z + 0.05)
alpha = np.clip((dist - 0.085) / 0.05, 0, 1) * SKIRT_PELVIS * zone
lg = {gi[n] for n in ('LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg') if n in gi}
bh = body.vertex_groups['Hips']; n_sk = 0
for vi in np.where(alpha > 0)[0]:
    moved = 0.0
    for gg in body.data.vertices[vi].groups:
        if gg.group in lg: take = gg.weight * alpha[vi]; gg.weight -= take; moved += take
    if moved: bh.add([int(vi)], moved, 'ADD'); n_sk += 1
print('skirt vertices shifted toward the pelvis:', n_sk)

rig.data.pose_position = 'POSE'
for ob in [o for o in bpy.data.objects if o.type == 'MESH' and o.parent_type == 'BONE']:
    for p in ob.data.polygons: p.use_smooth = True
bpy.ops.wm.save_as_mainfile(filepath=out)
print('DONE')
