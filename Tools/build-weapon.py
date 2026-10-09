# Blender: build a simple weapon or prop as a GLB, for heroes whose gear wasn't generated.
#   blender -b --factory-startup -P Tools/build-weapon.py -- <kind> out.glb [length_m] [ring_hex]
# Long things lie along +X, butt or pommel at the origin, tip toward +length:
#   spear     steel leaf blade, gold socket with a coloured ring, wooden shaft, gold butt (atossa/inputs/spear.png)
#   immortal  Bardiya's spear: bronze leaf head, gold pomegranate butt (bardiya/inputs/spear*.png)
#   khopesh   bronze sickle-sword; leather grip, straight shank, then a crescent whose sharp convex edge faces +Z
#   akinaka   Persian short sword: lobed pommel, butterfly guard, straight double-edged blade
#   sunstaff  gold staff topped by a small teal shrine and a crescent cradling a sun disc
#   standard  Roman eagle standard: pole, crossbar with a red banner, laurel wreath, spread-winged gold eagle
#   sistrum   Egyptian rattle: banded handle, gold loop with cross-rods and jingles
#   fan       open iron folding fan: dark ribs, cream leaf, spread in the XZ plane around +X
#   crossbow  Han crossbow: stock along +X (butt at 0), bronze trigger, prod across Y at the front, top +Z
# scabbard: dark leather sheath, mouth at the origin, tip toward -X (the sheath slot's convention).
# bow:      recurve bow centred on its grip, limbs along X, string on the +Z side.
# shield:   round wicker shield, face toward -Y, tall along Z, back face at y = 0.
# assemble-meshy-hero.py reads each from <meshy_dir>/<slot>/model_urls_glb.glb (see props.json there).
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
KIND, out = argv[0], argv[1]
L = float(argv[2]) if len(argv) > 2 else {'spear': 1.7, 'immortal': 2.0, 'khopesh': 0.6, 'akinaka': 0.5, 'sunstaff': 1.65,
     'standard': 2.0, 'sistrum': 0.36, 'fan': 0.32, 'crossbow': 0.85, 'scabbard': 0.4, 'bow': 1.2, 'shield': 0.8}[KIND]
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


def box(c, size, mat):
    """An axis-aligned box centred on c."""
    r = bmesh.ops.create_cube(bm, size=1.0)['verts']
    for v in r: v.co = Vector((c[0] + v.co.x * size[0], c[1] + v.co.y * size[1], c[2] + v.co.z * size[2]))
    for f in {f for v in r for f in v.link_faces}: f.material_index = mat


def rod(a, b, r, mat):
    """A thin round rod from point a to point b (a string, a cord)."""
    n0 = len(bm.verts); d = b - a
    lathe([(0, r), (d.length, r)], mat, seg=6)
    bm.verts.ensure_lookup_table()
    q = Vector((1, 0, 0)).rotation_difference(d.normalized())
    for v in bm.verts[n0:]: v.co = a + q @ v.co


def jingle(x, z, r, mat):
    """A small disc threaded on a rod (axis along Z) at (x, 0, z)."""
    n0 = len(bm.verts)
    lathe([(-0.25 * r, 0.25 * r), (0, r), (0.25 * r, 0.25 * r)], mat, seg=10)
    bm.verts.ensure_lookup_table()
    for v in bm.verts[n0:]: v.co = Vector((x + v.co.y, v.co.z, z + v.co.x))


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
elif KIND == 'immortal':
    R = 0.016
    WOOD, GOLD, BRONZE = material('wood', '5A3420', 0, 0.55), material('gold', 'C29A4E', 1, 0.35), material('bronze', 'B08A4A', 1, 0.3)
    # Pomegranate butt: a ribbed gold ball with a crown of little sepals at its foot.
    prof = [(0, 0.004)]
    for i in range(1, 13):
        a = math.pi * i / 12; prof.append((0.045 * (1 - math.cos(a)) + 0.012, 0.042 * math.sin(a) + 0.006))
    lathe([(0, 0.01), (0.012, 0.022)] + prof[1:] + [(0.106, 0.02), (0.13, 0.019), (0.14, R * 1.2)], GOLD, seg=16)
    lathe([(0.138, R), (L * 0.84, R)], WOOD)
    lathe([(L * 0.835, R * 1.1), (L * 0.845, R * 1.6), (L * 0.86, R * 1.3), (L * 0.865, R * 1.6), (L * 0.875, R * 1.1)], GOLD)
    x0, W, TH = L * 0.872, 0.07, 0.014
    loft([((x0 + t * (L - x0), 0), (0, 1), W / 2 * w, W / 2 * w, TH * max(w, 0.3))
          for t, w in ((0.0, 0.3), (0.1, 0.75), (0.28, 1.0), (0.55, 0.6), (0.8, 0.28), (0.95, 0.08))], BRONZE, tip=(L, 0))
    smooth = {WOOD, GOLD}
elif KIND == 'akinaka':
    k = L / 0.5
    LEATHER, GOLD, STEEL = material('leather', '2E1C12', 0, 0.7), material('gold', 'C29A4E', 1, 0.33), material('steel', 'B3B8BF', 1, 0.22)
    lathe([(0, 0.004 * k), (0.006 * k, 0.02 * k), (0.016 * k, 0.022 * k), (0.024 * k, 0.012 * k)], GOLD)      # pommel
    lathe([(0.022 * k, 0.012 * k), (0.06 * k, 0.014 * k), (0.1 * k, 0.012 * k)], LEATHER)                     # grip
    # Butterfly guard: two lobes flaring along the edge direction (Z), thin in Y.
    loft([((0.098 * k, 0), (0, 1), 0.016 * k, 0.016 * k, 0.02 * k), ((0.108 * k, 0), (0, 1), 0.045 * k, 0.045 * k, 0.018 * k),
          ((0.118 * k, 0), (0, 1), 0.03 * k, 0.03 * k, 0.014 * k), ((0.124 * k, 0), (0, 1), 0.016 * k, 0.016 * k, 0.012 * k)], GOLD)
    loft([((x * k, 0), (0, 1), w * k, w * k, 0.007 * k) for x, w in ((0.122, 0.02), (0.2, 0.019), (0.33, 0.017), (0.43, 0.012), (0.48, 0.006))],
         STEEL, tip=(L, 0))
    smooth = {LEATHER, GOLD}
elif KIND == 'scabbard':
    LEATHER, GOLD = material('leather', '3A1F14', 0, 0.6), material('gold', 'C29A4E', 1, 0.33)
    # Mouth at the origin, tip toward -X. Flat-oval section: wide along Z, thin along Y.
    st = [((-x, 0), (0, 1), w, w, 0.024) for x, w in ((0.0, 0.026), (0.03, 0.026), (0.2, 0.023), (0.33, 0.019))]
    loft(st, LEATHER)
    loft([((0.006, 0), (0, 1), 0.032, 0.032, 0.03), ((-0.03, 0), (0, 1), 0.032, 0.032, 0.03)], GOLD)          # throat
    loft([((-0.325, 0), (0, 1), 0.021, 0.021, 0.026), ((-L + 0.02, 0), (0, 1), 0.014, 0.014, 0.02)], GOLD, tip=(-L, 0))   # chape
    smooth = set()
elif KIND == 'sunstaff':
    R = 0.011
    GOLD, TEAL = material('gold', 'D3A94E', 1, 0.3), material('teal', '2A7C86', 0.2, 0.4)
    lathe([(0, R * 0.8), (0.03, R * 1.3), (0.05, R)], GOLD)
    lathe([(0.048, R), (L * 0.84, R)], GOLD)
    for x in (0.5, 0.62, 0.74):
        lathe([(L * x - 0.012, R * 1.05), (L * x, R * 1.5), (L * x + 0.012, R * 1.05)], TEAL)
    # A little shrine box, then the horns and disc.
    x0 = L * 0.84
    loft([((x0, 0), (0, 1), 0.03, 0.03, 0.05), ((x0 + 0.075, 0), (0, 1), 0.03, 0.03, 0.05)], TEAL)
    lathe([(x0 + 0.072, 0.03), (x0 + 0.085, 0.034), (x0 + 0.095, 0.014)], GOLD)
    # Horns: a crescent in the XZ plane (the side camera's view) opening toward the top (+X), cradling a sun disc.
    cx, Rh = x0 + 0.17, 0.08
    st = []
    for i in range(17):
        a = math.radians(100 + 160 * i / 16)
        n = Vector((math.cos(a), math.sin(a)))
        st.append(((cx + Rh * n.x, Rh * n.y), (n.x, n.y), 0.005, 0.014, 0.016))
    loft(st, GOLD)
    n0 = len(bm.verts)                                              # sun disc, facing Y
    lathe([(-0.008, 0.004), (-0.006, 0.05), (0.006, 0.05), (0.008, 0.004)], GOLD, seg=24)
    bm.verts.ensure_lookup_table()
    for v in bm.verts[n0:]: v.co = Vector((cx + v.co.y, v.co.x, v.co.z))
    smooth = {GOLD, TEAL}
elif KIND == 'standard':
    R = 0.017
    WOOD, GOLD, RED = material('wood', '5A3420', 0, 0.55), material('gold', 'D1A64A', 1, 0.3), material('red', 'A3161A', 0, 0.6)
    lathe([(0, R * 0.6), (0.06, R * 1.2), (0.08, R)], GOLD)
    lathe([(0.078, R), (L * 0.95, R)], WOOD)
    # Crossbar, banner, wreath and eagle all lie in the XZ plane, the one the side-on camera sees.
    xb = L * 0.72
    box((xb, 0, 0), (0.024, 0.024, 0.42), GOLD)                     # crossbar
    box((xb - 0.17, 0, 0), (0.34, 0.008, 0.36), RED)                # banner hangs below the bar
    box((xb - 0.33, 0, 0), (0.02, 0.012, 0.37), GOLD)               # fringe bar
    xw = L * 0.9                                                    # laurel wreath
    ring = [(xw + 0.06 * math.cos(2 * math.pi * i / 16), 0.06 * math.sin(2 * math.pi * i / 16)) for i in range(16)]
    for i in range(16):
        (x1, z1), (x2, z2) = ring[i], ring[(i + 1) % 16]
        box(((x1 + x2) / 2, 0, (z1 + z2) / 2), (abs(x2 - x1) + 0.016, 0.016, abs(z2 - z1) + 0.016), GOLD)
    # Eagle: a spread-winged silhouette in the XZ plane, extruded in Y.
    sil = [(0.0, 0.0), (0.03, 0.02), (0.05, 0.08), (0.11, 0.2), (0.15, 0.19), (0.12, 0.12), (0.1, 0.05), (0.13, 0.03),
           (0.15, 0.0), (0.13, -0.03), (0.1, -0.05), (0.12, -0.12), (0.15, -0.19), (0.11, -0.2), (0.05, -0.08), (0.03, -0.02)]
    x_e = L * 0.94
    top = [bm.verts.new((x_e + x, -0.012, z)) for x, z in sil]; bot = [bm.verts.new((x_e + x, 0.012, z)) for x, z in sil]
    bm.faces.new(top).material_index = GOLD; bm.faces.new(list(reversed(bot))).material_index = GOLD
    for i in range(len(sil)):
        j = (i + 1) % len(sil); bm.faces.new((top[i], top[j], bot[j], bot[i])).material_index = GOLD
    lathe([(x_e + 0.14, 0.022), (x_e + 0.17, 0.026), (x_e + 0.2, 0.012)], GOLD, seg=12)   # head
    smooth = {WOOD}
elif KIND == 'sistrum':
    k = L / 0.36
    GOLD, TEAL, RED = material('gold', 'D3A94E', 1, 0.3), material('teal', '23707A', 0.1, 0.45), material('red', '9A3A22', 0.1, 0.45)
    lathe([(0, 0.012 * k), (0.012 * k, 0.017 * k), (0.02 * k, 0.014 * k)], GOLD)
    for i, x in enumerate((0.02, 0.05, 0.08, 0.11, 0.14)):
        lathe([(x * k, 0.014 * k), ((x + 0.03) * k, 0.014 * k)], (TEAL, RED, TEAL, RED, TEAL)[i])
    lathe([(0.17 * k, 0.015 * k), (0.19 * k, 0.02 * k), (0.2 * k, 0.012 * k)], GOLD)
    # Loop: an oval band in the XZ plane, centred above the handle.
    cx, rx, rz = 0.28 * k, 0.085 * k, 0.05 * k
    st = []
    for i in range(25):
        a = math.radians(-90 + 360 * i / 24)
        n = Vector((math.cos(a) * rz, math.sin(a) * rx)).normalized()
        st.append(((cx + rx * math.sin(a), rz * math.cos(a)), (n.y, n.x), 0.005 * k, 0.005 * k, 0.012 * k))
    loft(st, GOLD)
    for x in (0.25, 0.29, 0.33):                                    # cross-rods along Z with jingles
        loft([((x * k, -0.075 * k), (1, 0), 0.0025 * k, 0.0025 * k, 0.005 * k), ((x * k, 0.075 * k), (1, 0), 0.0025 * k, 0.0025 * k, 0.005 * k)], GOLD)
        for zc in (-0.065, 0.065):
            jingle(x * k, zc * k, 0.012 * k, GOLD)
    smooth = {GOLD, TEAL, RED}
elif KIND == 'fan':
    WOOD, PAPER = material('wood', '3A2618', 0, 0.5), material('paper', 'E6DCC0', 0, 0.75)
    n, spread, r0 = 16, math.radians(150), 0.06
    for i in range(n + 1):                                          # ribs
        a = -spread / 2 + spread * i / n
        d = Vector((math.cos(a), 0, math.sin(a)))
        w = 0.004 if 0 < i < n else 0.007
        loft([((0, 0), (-d.z, d.x), w, w, 0.004), ((L * d.x, L * d.z), (-d.z, d.x), w * 0.7, w * 0.7, 0.003)], WOOD)
    leaf = []
    for i in range(n * 2 + 1):                                      # leaf: an annular sector, slightly pleated in Y
        a = -spread / 2 + spread * i / (n * 2)
        y = 0.006 if i % 2 else -0.006
        leaf.append((bm.verts.new((r0 * 3 * math.cos(a), y, r0 * 3 * math.sin(a))), bm.verts.new((L * 0.98 * math.cos(a), y, L * 0.98 * math.sin(a)))))
    for (a0, a1), (b0, b1) in zip(leaf, leaf[1:]):
        bm.faces.new((a0, b0, b1, a1)).material_index = PAPER
    lathe([(-0.01, 0.008), (0.01, 0.008)], WOOD, seg=10)            # rivet
    smooth = set()
elif KIND == 'crossbow':
    WOOD, BRONZE, STRING = material('wood', '3D2416', 0, 0.55), material('bronze', '8E7440', 1, 0.35), material('string', 'CFC6A8', 0, 0.8)
    box((0.08, 0, -0.02), (0.16, 0.05, 0.09), WOOD)                 # butt
    box((L * 0.55, 0, 0), (L * 0.9, 0.04, 0.045), WOOD)            # tiller
    box((L * 0.45, 0, 0.02), (0.1, 0.05, 0.05), BRONZE)             # trigger lock
    box((L * 0.45, 0, -0.05), (0.02, 0.014, 0.07), BRONZE)          # trigger
    box((L * 0.95, 0, 0), (0.05, 0.05, 0.06), BRONZE)               # prod socket
    # Prod: a shallow recurve across Y, bent back toward -X at the tips.
    for side in (-1, 1):
        st = [(L * 0.95 - 0.09 * (i / 8) ** 2, side * 0.37 * i / 8) for i in range(9)]
        for p0, p1 in zip(st, st[1:]):
            box(((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0), (abs(p1[0] - p0[0]) + 0.02, abs(p1[1] - p0[1]) + 0.012, 0.022), WOOD)
    tips = (L * 0.95 - 0.09, 0.37)
    for side in (-1, 1):                                            # string to the lock
        rod(Vector((tips[0], side * tips[1], 0.0)), Vector((L * 0.45, 0, 0.03)), 0.003, STRING)
    box((L * 0.7, 0, 0.035), (L * 0.55, 0.008, 0.008), BRONZE)      # bolt
    smooth = set()
elif KIND == 'bow':
    WOOD, HORN, STRING = material('wood', '6B3A1E', 0, 0.5), material('horn', 'D8C49A', 0, 0.5), material('string', 'D9D2BC', 0, 0.8)
    half = L / 2; st = []
    for i in range(-20, 21):
        t = i / 20; x = half * t
        z = -0.08 * (1 - t * t) + 0.05 * max(0, abs(t) - 0.75) ** 2 / 0.0625   # belly bends away from the string, tips recurve
        w = 0.016 if abs(t) < 0.12 else 0.011 * (1 - 0.5 * abs(t)) + 0.004
        st.append(((x, z), (0, 1), w, w, 0.022 if abs(t) < 0.12 else 0.013))
    loft(st, WOOD)
    for sgn in (-1, 1):
        loft([((sgn * half * 0.86, -0.08 * (1 - 0.74) + 0.05 * 0.0121 / 0.0625), (0, 1), 0.012, 0.012, 0.016),
              ((sgn * half * 0.9, -0.08 * (1 - 0.81) + 0.05 * 0.0225 / 0.0625), (0, 1), 0.012, 0.012, 0.016)], HORN)
    tz = 0.05 * 0.0625 / 0.0625
    loft([((-half * 0.98, tz), (0, 1), 0.0025, 0.0025, 0.003), ((half * 0.98, tz), (0, 1), 0.0025, 0.0025, 0.003)], STRING)
    smooth = {WOOD, HORN}
elif KIND == 'shield':
    WICKER, DARK, GOLD, RED, LEATHER = (material('wicker', 'B08A4E', 0, 0.75), material('wicker_dark', '7E5E30', 0, 0.8),
                                        material('gold', 'C9A04C', 1, 0.3), material('red', '7A2418', 0.2, 0.4), material('leather', '4A2E1C', 0, 0.7))
    D = L; R = D / 2; seg = 40; rings = 18
    # Front: concentric wicker courses in two tones, domed toward -Y; back face at y = 0.
    def ringv(r):
        return [bm.verts.new((r * math.cos(2 * math.pi * k / seg), -0.03 - 0.05 * (1 - (r / R) ** 2), r * math.sin(2 * math.pi * k / seg))) for k in range(seg)]
    prev = [bm.verts.new((0, -0.08, 0))]
    for i in range(1, rings + 1):
        cur = ringv(R * i / rings)
        mat = (WICKER, DARK)[i % 2] if i > 3 else GOLD
        if len(prev) == 1:
            for k in range(seg): bm.faces.new((prev[0], cur[k], cur[(k + 1) % seg])).material_index = mat
        else:
            for k in range(seg): bm.faces.new((prev[k], cur[k], cur[(k + 1) % seg], prev[(k + 1) % seg])).material_index = mat
        prev = cur
    back = [bm.verts.new((v.co.x, 0.0, v.co.z)) for v in prev]       # rim down to the flat back
    for k in range(seg): bm.faces.new((prev[k], back[k], back[(k + 1) % seg], prev[(k + 1) % seg])).material_index = LEATHER
    bm.faces.new(back).material_index = LEATHER
    n0 = len(bm.verts)
    lathe([(-0.12, 0.004), (-0.11, 0.035), (-0.09, 0.03)], RED, seg=16)    # boss jewel, lathed along X then turned to -Y
    bm.verts.ensure_lookup_table()
    for v in bm.verts[n0:]: v.co = Vector((v.co.y, v.co.x, v.co.z))
    smooth = {GOLD, RED}
else:
    sys.exit(f'unknown weapon {KIND}')

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new(KIND); bm.to_mesh(me); bm.free()
for m in mats: me.materials.append(m)
for p in me.polygons: p.use_smooth = p.material_index in smooth
ob = bpy.data.objects.new(KIND, me); bpy.context.scene.collection.objects.link(ob)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB')
print(KIND, round(L, 3), 'm ->', out)
