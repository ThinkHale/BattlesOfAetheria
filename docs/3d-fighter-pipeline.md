# 3D fighter and arena pipeline

Fighters and stages are modelled in 3D and rendered into the 2D art the game already plays:
side-on sprite strips (`App/Resources/Fighters`, read by `SpriteBody`) and painted stage
backdrops (`App/Resources/Stages/<stage>-far.jpg`, read by `StageNode`). The engine and app
code did not change.

Requirements: Blender 5.2 (`blender` on PATH), Python 3 with Pillow (and `gradio_client` for
the optional Qwen clean-up of reference views), and a Meshy API key as `MESHY_AI_KEY` in
`.env.local` (git-ignored). `python3 Tools/meshy.py balance` shows the remaining credits.

## A fighter (about 145 credits, 45 minutes)

Work happens in `art-inbox/3d/<hero>/` (git-ignored apart from `strips.json`).

1. **Reference views.** Use `docs/art/hero-modeling/views/<hero>/{front,side,back}.png`. Remove
   capes, sheathed weapons and quivers first (they are added as separate pieces), e.g. with
   the Qwen image-edit Space; save to `views/`. Crop weapon panels from the turnaround to `gear/`.
2. **Generate** with `Tools/meshy.py multi` into `meshy/armored` (body: a-pose, PBR, 4k,
   ~40k triangles) and one folder per prop: `gladius` (any sword), `sheath`, `shield`, `bow`,
   `quiver`, `cape`. Every prop is optional; a cape folder can be copied from another hero.
3. **Rig and animate:** `meshy.py rig meshy/rig --task <armored task id> --height <m>`, then
   `meshy.py animate meshy/anims --rig <rig task id> --actions <ids>`. The clip ids used so far
   are in each hero's `strips.json` notes below; preview new ones with
   `GET /openapi/v1/animations/library` (free).
4. **Assemble:** `blender -b -P Tools/assemble-meshy-hero.py -- meshy <Name>_game.blend <Name> [blade_m]`.
   Bakes fists (the rig has no finger bones), attaches props, simulates the cape as cloth and
   relaxes the skirt onto the hips.
5. **Render strips:** write `strips.json` (game strip -> clip, frame count, loop; `lock_rise`
   for jumps, `aim` for archery clips), then
   `blender -b -P Tools/render-strips.py -- <Name>_game.blend strips <hero_id> strips.json`.
6. **Install:** `python3 Tools/install-fighter-strips.py strips <hero_id>` (palette-compresses
   into `App/Resources/Fighters`), then `xcodegen generate`.

### A body made elsewhere and rigged in Mixamo (Atossa, Kepri)

Tripo bodies are rigged in Mixamo with no clips (Mixamo has no spear or sword-only sets). Instead the Meshy clips
already downloaded for other heroes are retargeted onto the Mixamo skeleton, so no credits are spent:

1. `blender -b -P Tools/retarget-mixamo-hero.py -- mixamo.fbx meshy/rigged.blend 1.78 <other heroes' meshy/anims/batch*.glb>`
   makes the standing T-pose the rest pose, renames bones to Meshy's, folds the fingers into the hands and rewires
   Tripo's material by texture file name (its FBX imports fully metallic, with the albedo also used as alpha or a
   normal map and the PBR maps miswired, which is why it looks dull in Mixamo; the textures themselves are untouched).
2. A missing weapon can be built: `blender -b -P Tools/build-weapon.py -- spear meshy/spear/model_urls_glb.glb 1.7`
   or `-- khopesh meshy/gladius/model_urls_glb.glb 0.6`.
3. Assemble and render as above (`assemble-meshy-hero.py` reads `rigged.blend` when there are no anim batches).
   Pass a fifth argument of `0` for a short kilt over bare thighs: the default skirt pass (0.65) moves anything far
   from the thigh bone onto the pelvis and tears muscular thighs.

`render-strips.py` widens or heightens a strip's frame, at the same pixels per metre, when a weapon or a fall would
be clipped; `fighter-<hero>.json` records each strip's size and feet line.

Check in the simulator with
`SIMCTL_CHILD_AETHERIA_START=fight:<hero>:<hero>:<stage>:demo xcrun simctl launch <device> com.thinkhale.aetheriaclash`.

| Hero | Clips (Meshy action ids) |
| --- | --- |
| gaius | 89,21,548,147,466,97,219,240,242,86,220,90,105,178,187,88,156,8 |
| marcus_varro | 89,21,9,147,466,219,240,221,102,86,220,242,92,179,190,101 |
| nefru | 231,228,468,150,466,225,206,207,215,86,220,224,222,179,190,412 |
| wei_jian | 89,21,9,147,466,219,240,199,102,86,220,127,238,179,190,41 |
| atossa | none bought: retargeted from the four heroes above (see `art-inbox/3d/atossa/strips.json`) |
| khepri | none bought: retargeted (see `art-inbox/3d/khepri/strips.json`); assembled with skirt 0 |

## An arena

`art-inbox/3d/arenas/pieces.tsv` lists the Meshy text-to-3D landmark pieces (30 credits each,
`meshy.py text`). `blender -b -P Tools/build-arena.py -- <stage> art-inbox/3d/arenas out.png 128`
lays them out with ground, distant ridges, sky, fires and haze and renders a 2048x1024 backdrop
(floor 17% up from the bottom, as `StageNode` expects). Save it as
`App/Resources/Stages/<stage>-far.jpg`.

`Tools/turntable-pbr.py` renders a four-side preview of any GLB.
