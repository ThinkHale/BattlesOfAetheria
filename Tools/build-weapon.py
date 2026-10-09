# Blender: build a simple weapon as a GLB, for heroes whose weapon wasn't generated.
#   blender -b --factory-startup -P Tools/build-weapon.py -- spear|khopesh out.glb [length_m] [ring_hex]
# spear:   steel leaf blade, gold socket with a coloured ring, wooden shaft, gold butt (atossa/inputs/spear.png).
# khopesh: bronze sickle-sword; leather grip, straight shank, then a crescent whose sharp convex edge faces +Z.
# Lies along +X, butt or pommel at the origin, tip toward +length. assemble-meshy-hero.py reads a spear from
# <meshy_dir>/spear/model_urls_glb.glb and any sword (khopesh included) from <meshy_dir>/gladius/model_urls_glb.glb.
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
KIND, out = argv[0], argv[1]
L = float(argv[2]) if len(argv) > 2 else {'spear': 1.7, 'khopesh': 0.6}[KIND]
ring_hex = argv[3] if len(argv) > 3 else '286D70'

bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(hexs):
    c = [int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1]


mats = []
def material(name, hexs, metal, rough):
    m = bpy.data.materials.new(name); b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(hexs); b.inputs['Metallic'].default_value = metal; b.inputs['Roughness'].default_value = rough
    mats.append(m); return len(mats) - 1


bm = bmesh.new()


def lathe(profile, mat, seg=20):
    """A turned part: profile is [(x, radius), ...] along the X axis."""
    rings = [[bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for a in (2 * math.pi * k / seg for k in range(seg))] for x, r in profile]
    for a_, b_ in zip(rings, rings[1:]):
        for k in range(seg): bm.faces.new((a_[k], a_[(k + 1) % seg], b_[(k + 1) % seg], b_[k])).material_index = mat
    bm.faces.new(list(reversed(rings[0]))).material_index = mat
    bm.faces.new(rings[-1]).material_index = mat


def loft(stations, mat, tip=None):
    """A flat blade: stations are (centre, normal, edge half-width, back half-width, thickness) in the XZ plane;
    the edge lies along +normal, the flats face Y."""
    rings = []
    for c, n, wo, wi, th in stations:
        c, n = Vector((c[0], 0, c[1])), Vector((n[0], 0, n[1])).normalized()
        rings.append([bm.verts.new(p) for p in (c + n * wo, c + Vector((0, th / 2, 0)), c - n * wi, c - Vector((0, th / 2, 0)))])
    for a_, b_ in zip(rings, rings[1:]):
        for k in range(4): bm.faces.new((a_[k], a_[(k + 1) % 4], b_[(k + 1) % 4], b_[k])).material_index = mat
    bm.faces.new(list(reversed(rings[0]))).material_index = mat
    if tip is not None:
        t = bm.verts.new((tip[0], 0, tip[1]))
        for k in range(4): bm.faces.new((rings[-1][k], rings[-1][(k + 1) % 4], t)).material_index = mat
    else:
        bm.faces.new(rings[-1]).material_index = mat


fx = lambda t: t * L
if KIND == 'spear':
    R = 0.0155                                                   # shaft radius
    WOOD, GOLD, RING, STEEL = (material('wood', '6B3E22', 0, 0.55), material('gold', 'C29A4E', 1, 0.35),
                               material('ring', ring_hex, 0, 0.4), material('steel', 'A9ADB3', 1, 0.25))
    lathe([(fx(0), R * 0.3), (fx(0.004), R * 0.7), (fx(0.018), R * 1.15), (fx(0.03), R * 0.9), (fx(0.034), R * 1.3),
           (fx(0.11), R * 1.25), (fx(0.118), R * 1.4), (fx(0.124), R * 1.0)], GOLD)                           # butt cap
    lathe([(fx(0.122), R), (fx(0.612), R)], WOOD)                                                             # shaft
    lathe([(fx(0.61), R * 1.05), (fx(0.616), R * 1.35), (fx(0.624), R * 1.1), (fx(0.725), R * 1.15)], GOLD)  # socket
    lathe([(fx(0.724), R * 1.3), (fx(0.738), R * 1.3)], RING)                                                 # ring
    lathe([(fx(0.737), R * 1.15), (fx(0.775), R * 1.25), (fx(0.785), R * 1.75), (fx(0.797), R * 1.75),
           (fx(0.805), R * 1.2), (fx(0.82), R * 0.9)], GOLD)                                                 # collar
    # Blade: a kite-shaped leaf with a diamond cross-section, widest a fifth of the way up.
    x0, W, TH = fx(0.81), 0.06, 0.013
    loft([((x0 + s * (L - x0), 0), (0, 1), W / 2 * w, W / 2 * w, TH * max(w, 0.3))
          for s, w in ((0.0, 0.35), (0.08, 0.8), (0.2, 1.0), (0.45, 0.72), (0.75, 0.36), (0.93, 0.1))], STEEL, tip=(L, 0))
    smooth = {WOOD, GOLD, RING}
elif KIND == 'khopesh':
    k = L / 0.6                                                  # designed at 0.6 m
    LEATHER, GOLD, BRONZE = material('leather', '3B2416', 0, 0.7), material('gold', 'C29A4E', 1, 0.35), material('bronze', 'A8743A', 1, 0.32)
    lathe([(0, 0.006 * k), (0.004 * k, 0.017 * k), (0.016 * k, 0.019 * k), (0.022 * k, 0.012 * k)], GOLD)   # pommel
    lathe([(0.02 * k, 0.0125 * k)] + [(x * k, r * k) for x, r in ((0.035, 0.015), (0.06, 0.0145), (0.085, 0.015), (0.11, 0.0145), (0.125, 0.013))], LEATHER)
    lathe([(0.122 * k, 0.014 * k), (0.128 * k, 0.018 * k), (0.138 * k, 0.018 * k), (0.144 * k, 0.012 * k)], GOLD)   # collar
    # Straight shank, then a crescent: an arc bending away from the edge (+Z), its convex side sharpened.
    st = [((x * k, 0), (0, 1), 0.011 * k, 0.011 * k, 0.009 * k) for x in (0.14, 0.22, 0.30)]
    R, a0, sweep = 0.32 * k, math.radians(105), math.radians(68)
    c = Vector((0.30 * k, 0)) - R * Vector((math.cos(a0), math.sin(a0)))
    for i in range(1, 15):
        s = i / 14; a = a0 - sweep * s; n = Vector((math.cos(a), math.sin(a)))
        p = c + R * n; grow = min(1, s / 0.15)
        st.append(((p.x, p.y), (n.x, n.y), (0.011 + 0.03 * grow * (1 - s ** 2)) * k, (0.011 - 0.003 * grow) * k * (1 - 0.7 * s), 0.008 * k * (1 - 0.5 * s)))
    a = a0 - sweep * 1.04; tip = c + R * Vector((math.cos(a), math.sin(a)))
    loft(st, BRONZE, tip=(tip.x, tip.y))
    smooth = {LEATHER, GOLD}
else:
    sys.exit(f'unknown weapon {KIND}')

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new(KIND); bm.to_mesh(me); bm.free()
for m in mats: me.materials.append(m)
for p in me.polygons: p.use_smooth = p.material_index in smooth
ob = bpy.data.objects.new(KIND, me); bpy.context.scene.collection.objects.link(ob)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB')
print(KIND, round(L, 3), 'm ->', out)
