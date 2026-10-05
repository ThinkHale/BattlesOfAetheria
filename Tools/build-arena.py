# Blender: compose an empire's fighting arena from Meshy-generated landmark pieces and render the game backdrop.
#   blender -b --factory-startup -P Tools/build-arena.py -- <stage> art-inbox/3d/arenas out.png [samples]
# Output contract (App/Sources/Game/StageNode.swift, painted mode): one opaque 2:1 image; the fighters' floor is 17%
# up from the bottom edge and the frame spans ~15.6 m at the fighting plane (a fighter is ~236 px tall at 2048 wide).
# The fighters stand on the y = 0 plane; the camera looks along +Y from the front; nothing is placed in front of them.
import bpy, sys, math, os, glob, random, numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
STAGE, ROOT, OUT = argv[:3]
SAMPLES = int(argv[3]) if len(argv) > 3 else 128
W, H = 2048, 1024
D, EYE, LENS = 15.2, 1.6, 35.0              # camera distance to the fighting plane, eye height, focal length (36 mm sensor)
GROUND_LINE = 0.17

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
random.seed(7)


# ---------------- helpers ----------------
def piece(name, x, y, height, rot_z=0.0, along_x=False):
    """Import a generated piece, turn it to face the camera (-Y), scale to `height` metres, base on the ground."""
    path = sorted(glob.glob(f'{ROOT}/{name}/*.glb'))[0]
    before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]; ms = [o for o in new if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms: o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1: bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM'); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o is not ob and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    if along_x: ob.data.transform(Matrix.Rotation(math.pi / 2, 4, 'Z'))
    co = np.array([v.co[:] for v in ob.data.vertices]); mn, mx = co.min(0), co.max(0)
    ob.data.transform(Matrix.Translation((-(mn[0] + mx[0]) / 2, -(mn[1] + mx[1]) / 2, -mn[2])))
    s = height / (mx[2] - mn[2]); ob.data.transform(Matrix.Scale(s, 4))
    ob.location = (x, y, 0); ob.rotation_euler = (0, 0, rot_z); ob.name = name
    return ob, (mx - mn) * s


def instance(src, x, y, rot_z=0.0, scale=1.0):
    ob = src.copy(); sc.collection.objects.link(ob); ob.location = (x, y, 0); ob.rotation_euler = (0, 0, rot_z); ob.scale = (scale,) * 3
    return ob


def mat(name, color, rough=0.8, emit=None, strength=0.0, metallic=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True; p = m.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = (*color, 1); p.inputs['Roughness'].default_value = rough; p.inputs['Metallic'].default_value = metallic
    if emit: p.inputs['Emission Color'].default_value = (*emit, 1); p.inputs['Emission Strength'].default_value = strength
    return m


def ground(kind, c1, c2, size=900):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, size / 2 - 30, 0)); g = bpy.context.object; g.name = 'ground'
    m = bpy.data.materials.new('ground'); m.use_nodes = True; nt = m.node_tree; p = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    if kind == 'pavers':
        t = nt.nodes.new('ShaderNodeTexBrick'); t.inputs['Scale'].default_value = 0.35; t.inputs['Mortar Size'].default_value = 0.012
        t.inputs['Color1'].default_value = (*c1, 1); t.inputs['Color2'].default_value = (*c2, 1); t.inputs['Mortar'].default_value = (*[c * 0.5 for c in c1], 1)
        nt.links.new(tc.outputs['Object'], t.inputs['Vector'])
        nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3; nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
        mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs['Factor'].default_value = 0.35
        nt.links.new(t.outputs['Color'], mix.inputs['A']); nt.links.new(nz.outputs['Color'], mix.inputs['B']); nt.links.new(mix.outputs['Result'], p.inputs['Base Color'])
        bump = nt.nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 0.4; nt.links.new(t.outputs['Fac'], bump.inputs['Height']); nt.links.new(bump.outputs['Normal'], p.inputs['Normal'])
    else:   # sand / earth: layered noise
        nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 0.25; nz.inputs['Detail'].default_value = 8
        nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
        ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color = (*c1, 1); ramp.color_ramp.elements[1].color = (*c2, 1)
        nt.links.new(nz.outputs['Fac'], ramp.inputs['Fac']); nt.links.new(ramp.outputs['Color'], p.inputs['Base Color'])
        fine = nt.nodes.new('ShaderNodeTexNoise'); fine.inputs['Scale'].default_value = 40; nt.links.new(tc.outputs['Object'], fine.inputs['Vector'])
        bump = nt.nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 0.3; nt.links.new(fine.outputs['Fac'], bump.inputs['Height']); nt.links.new(bump.outputs['Normal'], p.inputs['Normal'])
    p.inputs['Roughness'].default_value = 0.9
    g.data.materials.append(m)


def ridge(y, height, color, width=2400, seed=0, scale=0.004, sharp=False):
    """A far range of hills or mountains: a crest line at depth y, sloping away behind it."""
    rng = np.random.default_rng(seed)
    xs = np.linspace(-width / 2, width / 2, 401); depths = np.linspace(-20, 260, 30)
    prof = np.zeros_like(xs)
    for k, amp in ((1, 1.0), (2.3, 0.45), (5.1, 0.2), (11.7, 0.08)):
        ph = rng.uniform(0, 6.28); wave = np.sin(xs * scale * k * 6.28 + ph)
        prof += amp * (1 - np.abs(wave)) if sharp else amp * (wave * 0.5 + 0.5)
    prof = prof / prof.max() * height
    verts = []
    for d in depths:
        fall = np.clip(1 - abs(d - 40) / 220, 0, 1) ** 1.2 if d > 40 else np.clip((d + 20) / 60, 0, 1)
        verts += [(float(x), y + float(d), float(h * fall)) for x, h in zip(xs, prof)]
    n = len(xs); faces = [(j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i) for j in range(len(depths) - 1) for i in range(n - 1)]
    me = bpy.data.meshes.new('ridge'); me.from_pydata(verts, [], faces); me.update()
    for p in me.polygons: p.use_smooth = True
    r = bpy.data.objects.new('ridge', me); sc.collection.objects.link(r)
    me.materials.append(mat('ridge', color, 0.95)); return r


def pyramid(x, y, base, color):
    h = base * 0.64
    verts = [(-base / 2, -base / 2, 0), (base / 2, -base / 2, 0), (base / 2, base / 2, 0), (-base / 2, base / 2, 0), (0, 0, h)]
    me = bpy.data.meshes.new('pyr'); me.from_pydata(verts, [], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)]); me.update()
    ob = bpy.data.objects.new('pyramid', me); sc.collection.objects.link(ob); ob.location = (x, y, 0); ob.rotation_euler = (0, 0, math.radians(18))
    m = bpy.data.materials.new('pyr'); m.use_nodes = True; nt = m.node_tree; p = nt.nodes['Principled BSDF']
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 0.08; ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*[c * 0.8 for c in color], 1); ramp.color_ramp.elements[1].color = (*color, 1)
    nt.links.new(nz.outputs['Fac'], ramp.inputs['Fac']); nt.links.new(ramp.outputs['Color'], p.inputs['Base Color']); p.inputs['Roughness'].default_value = 0.95
    me.materials.append(m)


def fire(x, y, z, size=0.5, power=600, color=(1.0, 0.55, 0.2)):
    """Flame: a glowing teardrop plus a warm point light."""
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=size * 0.42, radius2=0.0, depth=size * 1.5, location=(x, y, z + size * 0.6))
    f = bpy.context.object; bpy.ops.object.shade_smooth()
    f.data.materials.append(mat('flame', (1.0, 0.45, 0.12), 1.0, emit=(1.0, 0.38, 0.08), strength=3.5))
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=size * 0.22, radius2=0.0, depth=size * 0.9, location=(x, y - 0.05, z + size * 0.4))
    bpy.context.object.data.materials.append(mat('core', (1.0, 0.8, 0.4), 1.0, emit=(1.0, 0.70, 0.30), strength=5))
    l = bpy.data.lights.new('fire', 'POINT'); l.energy = power; l.color = color; l.shadow_soft_size = 0.3
    lo = bpy.data.objects.new('fire', l); sc.collection.objects.link(lo); lo.location = (x, y, z + size)


def sky(horizon, zenith, sun_az, sun_elev, sun_color, glow=1.0, strength=1.0, sun_energy=3.5, fill=0.6):
    """Painted sky: a horizon-to-zenith gradient plus a sun glow at a chosen direction (azimuth from +Y, the view
    direction, toward +X), with a sun lamp and a soft frontal fill aimed to match."""
    az, el = math.radians(sun_az), math.radians(sun_elev)
    sd = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    w = bpy.data.worlds.new('sky'); sc.world = w; w.use_nodes = True; nt = w.node_tree; bg = nt.nodes['Background']
    tc = nt.nodes.new('ShaderNodeTexCoord'); nrm = nt.nodes.new('ShaderNodeVectorMath'); nrm.operation = 'NORMALIZE'
    nt.links.new(tc.outputs['Generated'], nrm.inputs[0])
    sep = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(nrm.outputs[0], sep.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange'); mr.inputs['From Min'].default_value = 0.0; mr.inputs['From Max'].default_value = 0.55
    nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
    ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color = (*horizon, 1); ramp.color_ramp.elements[1].color = (*zenith, 1)
    ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[1].position = 1.0
    nt.links.new(mr.outputs['Result'], ramp.inputs['Fac'])
    dot = nt.nodes.new('ShaderNodeVectorMath'); dot.operation = 'DOT_PRODUCT'; dot.inputs[1].default_value = sd
    nt.links.new(nrm.outputs[0], dot.inputs[0])
    halo = nt.nodes.new('ShaderNodeMath'); halo.operation = 'POWER'; halo.inputs[1].default_value = 24; halo.use_clamp = True
    nt.links.new(dot.outputs['Value'], halo.inputs[0])
    disc = nt.nodes.new('ShaderNodeMath'); disc.operation = 'POWER'; disc.inputs[1].default_value = 2500; nt.links.new(dot.outputs['Value'], disc.inputs[0])
    tot = nt.nodes.new('ShaderNodeMath'); tot.operation = 'MULTIPLY_ADD'; tot.inputs[1].default_value = 1.0
    nt.links.new(halo.outputs[0], tot.inputs[0]); nt.links.new(disc.outputs[0], tot.inputs[2])
    k = nt.nodes.new('ShaderNodeMath'); k.operation = 'MULTIPLY'; k.inputs[1].default_value = glow; nt.links.new(tot.outputs[0], k.inputs[0])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'ADD'; mix.clamp_result = False
    mix.inputs['B'].default_value = (*sun_color, 1)
    nt.links.new(k.outputs[0], mix.inputs['Factor']); nt.links.new(ramp.outputs['Color'], mix.inputs['A'])
    nt.links.new(mix.outputs['Result'], bg.inputs['Color']); bg.inputs['Strength'].default_value = strength
    def lamp(name, direction, energy, color, angle):
        l = bpy.data.lights.new(name, 'SUN'); l.energy = energy; l.color = color; l.angle = math.radians(angle)
        o = bpy.data.objects.new(name, l); sc.collection.objects.link(o)
        o.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler(); return o
    lamp('sun', sd, sun_energy, sun_color, 1.5)
    lamp('fill', Vector((-0.4, -1.0, 0.35)).normalized(), fill, (1.0, 0.92, 0.85), 10)   # soft light from in front so facades read


def haze(color, density, near=70, far=900):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, (near + far) / 2, 60)); v = bpy.context.object; v.name = 'haze'
    v.scale = (3000, far - near, 120)
    m = bpy.data.materials.new('haze'); m.use_nodes = True; nt = m.node_tree; nt.nodes.remove(nt.nodes['Principled BSDF'])
    vol = nt.nodes.new('ShaderNodeVolumePrincipled'); vol.inputs['Color'].default_value = (*color, 1); vol.inputs['Density'].default_value = density
    nt.links.new(vol.outputs[0], nt.nodes['Material Output'].inputs['Volume']); v.data.materials.append(m)


# ---------------- layouts ----------------
if STAGE == 'forum':          # The Forum at dusk: temples, colonnades, braziers, a red sunset
    sky((1.0, 0.42, 0.22), (0.10, 0.08, 0.20), -20, 6, (1.0, 0.55, 0.28), glow=2.5, strength=1.0, sun_energy=3.0)
    ground('pavers', (0.42, 0.36, 0.30), (0.50, 0.43, 0.35))
    ridge(260, 38, (0.24, 0.16, 0.18), seed=1, scale=0.006)
    t, _ = piece('rome_temple', 2, 46, 17)
    a, _ = piece('rome_arch', -21, 30, 13)
    a2 = instance(a, 34, 80, scale=1.0); a2.rotation_euler = (0, 0, math.radians(-20))
    b, _ = piece('rome_brazier', -6.4, 3.2, 1.3)
    instance(b, 6.4, 3.2)
    for x in (-6.4, 6.4): fire(x, 3.2, 1.25, 0.55)
    t2 = instance(t, -44, 95, scale=0.9); t2.rotation_euler = (0, 0, math.radians(18))
    haze((0.95, 0.55, 0.40), 0.0007)
elif STAGE == 'nile':         # Banks of the Nile: pyramids, obelisks, palms, golden afternoon
    sky((1.0, 0.70, 0.38), (0.20, 0.42, 0.80), 42, 16, (1.0, 0.75, 0.45), glow=2.0, strength=0.55, sun_energy=2.6, fill=0.35)
    ground('sand', (0.42, 0.24, 0.08), (0.55, 0.36, 0.13))
    ridge(650, 25, (0.45, 0.33, 0.20), seed=2, scale=0.0025)
    pyramid(-120, 420, 150, (0.85, 0.70, 0.48)); pyramid(40, 520, 110, (0.82, 0.67, 0.45)); pyramid(170, 470, 70, (0.80, 0.66, 0.46))
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 120, 0.05)); river = bpy.context.object; river.scale = (3000, 60, 1)
    river.data.materials.append(mat('river', (0.10, 0.22, 0.25), 0.05))
    piece('egypt_pylon', 0, 40, 18)
    o, _ = piece('egypt_obelisk', -11, 18, 15); instance(o, 12, 20)
    p, _ = piece('egypt_palm', -16, 9, 10)
    for x, y, s_ in ((17, 12, 0.9), (-30, 40, 1.1), (34, 46, 1.0), (-48, 70, 1.2), (60, 95, 1.1), (-6, 75, 0.9)): instance(p, x, y, random.uniform(0, 6.28), s_)
    haze((0.95, 0.82, 0.62), 0.00012)
elif STAGE == 'persepolis':   # Gate of All Nations: bull-capital columns, Zagros mountains, amber light
    sky((1.0, 0.62, 0.35), (0.22, 0.25, 0.42), 30, 9, (1.0, 0.65, 0.35), glow=1.8, strength=0.55, sun_energy=2.4, fill=0.35)
    ground('pavers', (0.27, 0.22, 0.18), (0.33, 0.27, 0.22))
    ridge(380, 160, (0.20, 0.15, 0.14), seed=3, scale=0.003, sharp=True)
    ridge(650, 260, (0.28, 0.22, 0.22), seed=4, scale=0.002, sharp=True)
    piece('persia_gate', 0, 30, 15)
    c, _ = piece('persia_column', -40, 52, 17)
    for row, y in enumerate((52, 66)):
        for x in np.arange(-40, 44, 8):
            if (row, x) != (0, -40) and abs(x) > 9: instance(c, float(x), y)
    al, _ = piece('persia_altar', -6.5, 3.4, 1.6); instance(al, 6.5, 3.4)
    for x in (-6.5, 6.5): fire(x, 3.4, 1.55, 0.45)
    haze((0.95, 0.70, 0.45), 0.00012)
elif STAGE == 'greatWall':    # Juyan watchtower on the Great Wall at dusk, red lanterns on a rope
    sky((0.95, 0.40, 0.30), (0.08, 0.07, 0.18), 35, 3, (1.0, 0.45, 0.25), glow=2.2, strength=0.7, sun_energy=2.2, fill=0.35)
    ground('sand', (0.36, 0.30, 0.24), (0.45, 0.38, 0.30))
    ridge(420, 120, (0.22, 0.20, 0.24), seed=5, scale=0.0035, sharp=True)
    ridge(750, 220, (0.30, 0.27, 0.32), seed=6, scale=0.0022, sharp=True)
    wall, dims = piece('han_wall', 0, 34, 7.5, along_x=True)
    step = dims[0] * 0.98
    for k in range(-5, 6):
        if k: instance(wall, k * step, 34 + abs(k) * 1.5)
    piece('han_tower', 9, 33, 17)
    tw = instance(bpy.data.objects['han_tower'], -70, 140, scale=0.8)
    # Lanterns on a rope strung between two poles behind the fighters.
    pole_m = mat('pole', (0.18, 0.11, 0.07), 0.7)
    for x in (-9.5, 9.5):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=4.6, location=(x, 5.5, 2.3)); bpy.context.object.data.materials.append(pole_m)
    pts = [(-9.5 + 19 * t_, 5.5, 4.4 - 0.9 * math.sin(math.pi * t_)) for t_ in np.linspace(0, 1, 24)]
    curve = bpy.data.curves.new('rope', 'CURVE'); curve.dimensions = '3D'; sp = curve.splines.new('POLY'); sp.points.add(len(pts) - 1)
    for i, p_ in enumerate(pts): sp.points[i].co = (*p_, 1)
    curve.bevel_depth = 0.015; rope = bpy.data.objects.new('rope', curve); sc.collection.objects.link(rope); curve.materials.append(mat('rope', (0.25, 0.18, 0.1), 0.9))
    ln, _ = piece('han_lantern', -6.3, 5.5, 0.9)
    for i, t_ in enumerate(np.linspace(0.17, 0.83, 5)):
        x = -9.5 + 19 * t_; z = 4.4 - 0.9 * math.sin(math.pi * t_) - 0.92
        L = ln if i == 0 else instance(ln, 0, 0); L.location = (x, 5.5, z)
        l = bpy.data.lights.new('lantern', 'POINT'); l.energy = 120; l.color = (1.0, 0.35, 0.2)
        lo = bpy.data.objects.new('lantern', l); sc.collection.objects.link(lo); lo.location = (x, 4.6, z - 0.3)
    haze((0.55, 0.40, 0.50), 0.0007)
else:
    sys.exit(f'no layout for {STAGE}')

# ---------------- camera and render ----------------
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = LENS; cam.data.sensor_width = 36; cam.data.sensor_fit = 'HORIZONTAL'
cam.location = (0, -D, EYE); cam.rotation_euler = (math.radians(90), 0, 0)
frame_w = D * 36 / LENS                                  # metres across the frame at the fighting plane
frame_h = frame_w * H / W
centre_z = -GROUND_LINE * frame_h + frame_h / 2          # floor line at 17% from the bottom
cam.data.shift_y = (centre_z - EYE) / frame_w
cam.data.clip_end = 5000
print('frame %.2f x %.2f m at the fighting plane; fighter ~%.0f px tall' % (frame_w, frame_h, 1.8 / frame_w * W))

sc.render.engine = 'CYCLES'; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for d_ in prefs.devices: d_.use = True
    sc.cycles.device = 'GPU'
except Exception as e: print('GPU unavailable, using CPU:', e)
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
sc.render.image_settings.file_format = 'PNG'; sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(OUT)[0] + '.blend')
print('DONE', OUT)
