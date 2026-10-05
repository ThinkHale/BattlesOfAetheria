"""Install rendered fighter strips into the app, palette-compressed (about 8x smaller, visually identical).

usage: install-fighter-strips.py <strips_dir> <hero_id>   (needs Pillow)
Copies fighter-<hero>.json and every fighter-<hero>-<strip>.png into App/Resources/Fighters.
"""
import json, os, shutil, sys
from PIL import Image

src, hero = sys.argv[1], sys.argv[2]
dst = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'App/Resources/Fighters')
spec = json.load(open(os.path.join(src, f'fighter-{hero}.json')))
total = 0
for strip in spec:
    name = f'fighter-{hero}-{strip}.png'
    im = Image.open(os.path.join(src, name)).convert('RGBA')
    im.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(os.path.join(dst, name), optimize=True)
    total += os.path.getsize(os.path.join(dst, name))
shutil.copy(os.path.join(src, f'fighter-{hero}.json'), dst)
print(f'installed {len(spec)} strips for {hero}: {total / 1e6:.1f} MB')
