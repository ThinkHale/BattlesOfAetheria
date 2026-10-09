# Blender: render a rigged hero's actions into the sprite strips App/Sources/Game/SpriteBody.swift plays.
#   blender -b --factory-startup -P Tools/render-strips.py -- hero.blend out_dir hero_id spec.json
# spec.json maps game strip names to {"action": <Blender action name>, "frames": n, "loop": bool, "range": [a, b]?}.
# Writes out_dir/fighter-<hero>-<strip>.png (frames side by side, transparent) and out_dir/fighter-<hero>.json.
import bpy, sys, os, json, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
src, out, hero, spec_path = argv
spec = json.load(open(spec_path))
os.makedirs(out, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=src)
sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
hips = 'mixamorig:Hips' if 'mixamorig:Hips' in rig.data.bones else 'Hips'

FRAME = 512                     # px per frame, square
ORTHO = 2.6                     # metres across a frame
GROUND = 0.90                   # feet line, as a fraction of frame height from the top
PX_PER_M = FRAME / ORTHO
BELOW = (1 - GROUND) * ORTHO    # metres of frame under the feet
# A strip whose figure or weapon would be clipped (a lance, a long fall) gets a wider and/or taller frame at the
# same pixels per metre; fighter-<hero>.json carries each strip's size and feet line, which SpriteBody honours.
MARGIN = 0.05

# ---- look: transparent background, neutral studio light (the stage supplies colour and shadow) ----
sc.render.engine = 'BLENDER_EEVEE'
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = FRAME
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
if hasattr(sc.eevee, 'taa_render_samples'): sc.eevee.taa_render_samples = 24
world = bpy.data.worlds.new('studio'); sc.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.35, 0.33, 0.32, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.5
for o in [o for o in bpy.data.objects if o.type in ('LIGHT', 'CAMERA')]: bpy.data.objects.remove(o)
for o in bpy.data.objects:
    if o.type == 'MESH' and o.name.lower().startswith(('plane', 'ground')): bpy.data.objects.remove(o)


def sun(name, energy, color, rot):
    l = bpy.data.lights.new(name, 'SUN'); l.energy = energy; l.color = color; l.angle = math.radians(4)
    ob = bpy.data.objects.new(name, l); sc.collection.objects.link(ob); ob.rotation_euler = [math.radians(a) for a in rot]


sun('key', 3.6, (1.0, 0.9, 0.78), (55, 0, -120))     # from the front-left of a fighter facing screen-right
sun('rim', 2.6, (0.7, 0.8, 1.0), (60, 0, 70))
sun('fill', 0.8, (1, 1, 1), (75, 0, -40))

cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = ORTHO
# Side-on from -X: screen-right is -Y, which is the way the hero faces. Feet sit at GROUND, origin centred.
centre_z = (GROUND - 0.5) * ORTHO
cam.location = Vector((-10, 0, centre_z)); cam.rotation_euler = Vector((1, 0, 0)).to_track_quat('-Z', 'Y').to_euler()

ad = rig.animation_data or rig.animation_data_create()
for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
sheet = {}
from bpy_extras import anim_utils
for strip, s in spec.items():
    act = bpy.data.actions[s['action']]
    ad.action = act
    if act.slots: ad.action_slot = act.slots[0]
    a, b = s.get('range', act.frame_range); a, b = int(a), int(b)
    n = s['frames']
    picks = sorted({int(round(a + (b - a) * (k / n if s['loop'] else k / max(1, n - 1)))) for k in range(n)})
    n = len(picks)
    # Cloth needs every frame in order: start 40 frames early (the clip's first pose holds) so the cape settles.
    for ob in bpy.data.objects:
        for m in ob.modifiers:
            if m.type == 'CLOTH':
                m.point_cache.frame_start = a - 40; m.point_cache.frame_end = b + 1
    sc.frame_start, sc.frame_end = a - 40, b + 1
    bpy.ops.ptcache.free_bake_all()
    if any(m.type == 'CLOTH' for ob in bpy.data.objects for m in ob.modifiers):
        bpy.ops.ptcache.bake_all(bake=True)                  # renders then read the cache instead of re-simulating
    frames = []
    # "aim": turn the whole figure so the bow arm (spine -> left hand) points at the opponent (-Y) at the clip's
    # middle frame; archery clips aim off to the archer's side.
    root = rig.parent
    if root is not None:
        root.rotation_euler.z = root.get('base_yaw', root.rotation_euler.z); root['base_yaw'] = root.rotation_euler.z
        if s.get('aim'):
            sc.frame_set(int((a + b) / 2)); bpy.context.view_layer.update()
            d = (rig.matrix_world @ rig.pose.bones['LeftHand'].head) - (rig.matrix_world @ rig.pose.bones['Spine02'].head); d.z = 0
            if d.length > 1e-3:
                root.rotation_euler.z += math.atan2(d.x, -d.y) + math.pi   # rotate d onto (0, -1)
            bpy.context.view_layer.update()
    rig.data.pose_position = 'REST'; bpy.context.view_layer.update()
    rest_hips = rig.matrix_world @ rig.pose.bones[hips].head
    rig.data.pose_position = 'POSE'

    def follow(f):
        # Keep him in place: the fight engine moves him, so the camera follows his hips sideways (and, for jumps,
        # cancels any rise above standing height, since the engine lifts him too).
        sc.frame_set(f)
        hp = rig.matrix_world @ rig.pose.bones[hips].head
        return hp.y - rest_hips.y, (max(0.0, hp.z - rest_hips.z) if s.get('lock_rise') else 0.0)

    # Frame size: the standard square unless something in these frames reaches past it.
    half, top = ORTHO / 2, GROUND * ORTHO
    shown = [o for o in bpy.data.objects if o.type == 'MESH' and not o.hide_render]
    for f in picks:
        cy, cz = follow(f); dg = bpy.context.evaluated_depsgraph_get()
        for o in shown:
            ev = o.evaluated_get(dg); m = ev.to_mesh(); co = np.empty(len(m.vertices) * 3); m.vertices.foreach_get('co', co)
            ev.to_mesh_clear(); co = co.reshape(-1, 3) @ np.array(o.matrix_world.to_3x3()).T + np.array(o.matrix_world.translation)
            half = max(half, float(np.abs(co[:, 1] - cy).max()) + MARGIN); top = max(top, float((co[:, 2] - cz).max()) + MARGIN)
    fw, fh = int(math.ceil(half * PX_PER_M - 1e-6)) * 2, int(math.ceil((top + BELOW) * PX_PER_M - 1e-6))
    sc.render.resolution_x, sc.render.resolution_y = fw, fh
    cam.data.ortho_scale = max(fw, fh) / PX_PER_M
    for f in picks:
        cy, cz = follow(f)
        cam.location.y = cy
        cam.location.z = (fh / PX_PER_M) / 2 - BELOW + cz
        path = f'{out}/_tmp_{strip}_{len(frames):02d}.png'; sc.render.filepath = path
        bpy.ops.render.render(write_still=True); frames.append(path)
    # Paste the frames side by side.
    W = fw * n
    canvas = np.zeros((fh, W, 4), np.float32)
    for k, p in enumerate(frames):
        im = bpy.data.images.load(p); buf = np.empty(fw * fh * 4, np.float32); im.pixels.foreach_get(buf)
        canvas[:, k * fw:(k + 1) * fw] = buf.reshape(fh, fw, 4); bpy.data.images.remove(im); os.remove(p)
    img = bpy.data.images.new(f'fighter-{hero}-{strip}', W, fh, alpha=True)
    img.pixels.foreach_set(canvas.ravel()); img.filepath_raw = f'{out}/fighter-{hero}-{strip}.png'; img.file_format = 'PNG'; img.save()
    fps = n / (max(1, b - a) / 30.0)
    sheet[strip] = dict(frames=n, width=fw, height=fh, anchor=[0.5, round(1 - BELOW * PX_PER_M / fh, 4)], loop=bool(s['loop']),
                        figureHeight=round(1.8 * PX_PER_M, 1), fps=round(fps, 2))
    print('strip', strip, n, 'frames from', act.name, '%.0f-%.0f' % (a, b), flush=True)
json.dump(sheet, open(f'{out}/fighter-{hero}.json', 'w'), indent=1)
print('DONE', len(sheet), 'strips')
