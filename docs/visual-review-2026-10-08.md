# Graphics and visual code review — October 8, 2026

Scope: stage presentation, combat VFX, HUD, portraits, menus, asset loading, and icon delivery. 3D character models are excluded. This is a source review with existing marketing screenshots used as historical visual references; no current simulator run or performance capture was performed. Findings below distinguish code defects from expansion proposals. Gameplay code has not been changed.

## Findings, in priority order

### 1. P1 — Painted far layers disable the layered stage contract

Evidence: `App/Sources/Game/StageNode.swift:103–124` treats any `stageLayer(stage, "far")` as a complete painting and returns immediately. The later far-layer branch at line 143 cannot succeed because the same lookup already returned. Imported mid/floor paintings (`Tools/import-art.swift:265–274`) consequently never render when a far painting exists. The four bundled `*-far.jpg` stages currently take this early-return path. Animated braziers, river shimmer, foreground props, and other drawn stage details are also skipped.

Recommendation: explicitly distinguish a full backdrop from a layered stage in a small stage manifest, rather than inferring the mode from the presence of `far`. Preserve the current full paintings in backdrop mode; allow far/mid/floor assets and their intended parallax to compose in layered mode. Give each stage its own ground line and layer dimensions.

Validation: use a fixture with three obviously different layers, confirm all are visible, then test maximum separation and jumps on both iPhone and iPad for floor alignment and exposed edges.

### 2. P2 — HUD animation overwrites iPad sizing

Evidence: `App/Sources/Game/HUD.swift:87–92` scales the HUD up to 1.6×, but `showCombo` (lines 118–126) animates the same node back to 1×. `announce` (lines 132–144) similarly replaces the layout scale with fixed 1.6/1/1.15 values. An animated combo or announcement therefore loses the layout's device scale.

Recommendation: put animated content inside a wrapper whose scale is owned by layout, or multiply animation targets by the current UI scale. Recalculate health-bar width from the available half-screen on resize; it is currently fixed at initialization (line 26), while safe-area insets are also captured only once.

Validation: on a tall iPad, compare idle and animated HUD elements, then resize the view while an announcement is visible. Confirm names, meter labels, pips, and timer do not overlap.

### 3. P2 — Presentation timers advance per rendered frame, not simulation tick

Evidence: `FightScene.update` (`App/Sources/Game/FightScene.swift:191–196`) may execute up to four simulation ticks before one `renderFrame`. That frame invokes `hud.update` (line 454), where `HUDNode.tick` advances once (`HUD.swift:108–115`). Combo visibility, trailing damage delay, and blink timing therefore vary when frame delivery drops. `ProjectileNode.age` likewise advances once per render (`Effects.swift:241–246`).

Recommendation: drive gameplay-related presentation timers from `match.frameCount` or tick deltas; drive decorative fades and pulses from elapsed presentation time. Choose deliberately whether each effect follows hitstop and KO slow motion.

Validation: compare a recorded sequence at 60 fps and with 30 fps rendering; combo hold time and damage-bar catch-up should follow the chosen clock consistently.

### 4. P2 — The sunbeam trail's target is assigned before attachment

Evidence: `App/Sources/Game/Effects.swift:188` assigns `trail.targetNode = self.parent` inside `ProjectileNode.init`. The projectile is added to `world` only after initialization (`FightScene.swift:443–444`), so that assignment receives nil. The intended world-space trail is not established.

Recommendation: assign the emitter target after adding the projectile to the world, or pass the target into initialization. Check removal timing too: the current projectile fade removes its child emitter after 0.1 seconds, shorter than the particles' 0.5-second lifetime.

Validation: capture a moving sunbeam and confirm emitted particles remain behind it, rather than following the beam rigidly, and fade naturally after expiry.

### 5. P2 — Reduce Motion covers shake but leaves large presentation motion active

Evidence: `FightScene.swift:378` checks Reduce Motion for screen shake, but super cut-ins still traverse the screen (`383–426`), KO still triggers zoom (`341–344`), and title pulsing and selection springs remain unconditional (`UI/MenuViews.swift:32–43`, `UI/SelectViews.swift:138–139`).

Recommendation: centralize a presentation motion preference. Offer a stationary super card, immediate or gentle opacity transitions, and no KO zoom when Reduce Motion is enabled. Keep essential attack and projectile motion readable.

Validation: run the same title → selection → super → KO sequence with Reduce Motion on and off.

### 6. Performance opportunity — Bound and size the image cache

Evidence: `App/Sources/Services/ArtLibrary.swift:7–19` performs file lookup and UIImage creation on the main actor, retains successful full-size images indefinitely, and does not cache misses. `purge()` at line 41 has no call sites. Portraits are used at very different sizes in menu tiles, HUD medallions, and super cut-ins.

Recommendation: provide size-aware downsampled variants, prepare selected stage/portrait assets before the fight, share SpriteKit textures where practical, and use a bounded cache with a memory-pressure eviction path. Cache missing resource keys so fallback stages do not repeatedly search the bundle. Measure before introducing a more complex asset pipeline; this review does not establish an actual frame-time or memory regression.

Validation: compare cold selection/fight transition latency and peak memory after visiting all heroes and stages. Existing `-showFPS` support (`UI/FightView.swift:114–116`) is useful for a first check; a trace is needed for attribution.

### 7. Visual consistency opportunity — Preview the actual arena

Evidence: stage selection uses chronicle backdrops (`App/Sources/UI/SelectViews.swift:203,219`), whereas fights use `Stages/<id>-far` or drawn geometry. The chosen field's preview can therefore differ from the actual arena.

Recommendation: ship a stage thumbnail alongside the stage manifest, generated from the composed arena at a representative camera position. Preserve the chronicle paintings for lore screens. Add empire crests and a selected-state plaque to give the cards more identity.

### 8. Asset maintenance opportunity — Icon regeneration can overwrite the new artwork

Evidence: `Tools/make-icon.swift:140–143` always replaces both the app icon and marketing icon with the procedural version. `Tools/import-art.swift:280–283` replaces only the app icon, leaving marketing and website copies behind. The launch mark is separately drawn at line 142.

Recommendation: make generated art the documented source of truth, keep explicit paths for app/marketing/site exports, and label procedural generation as an intentional fallback. Create a separately authored transparent launch emblem if the launch screen should use the new sculpted style; removing red marble from the opaque icon is a separate art task.

## Expansion roadmap

| Order | Opportunity | Implementation surface | Relative effort |
| --- | --- | --- | --- |
| 1 | Restore the layered stage contract and fix HUD scaling/timing | StageNode, HUD, FightScene | Medium |
| 2 | Add restrained animated arena details: Nile shimmer/reeds, Forum brazier light, Persian banners, Han embers, Crossing beacon/mist | Stage manifest + StageNode | Medium |
| 3 | Give guard, armour, counter, clash, and each empire's super distinct silhouettes and textures | Effects + FightScene event dispatch | Medium |
| 4 | Extend the icon's crimson marble, embossed gold, and ivory material language into menu headers, crests, plaques, and round markers | Theme, MenuViews, HUD | Small–medium |
| 5 | Improve combat readability with bounded outlined callouts and condition glyphs; show combo damage already passed to showCombo but unused | Effects.floatingText, HUD.showCombo, SideBar | Small–medium |
| 6 | Use metadata-driven portrait focal points for tiles, medallions, and cut-ins; replace fixed crop assumptions | ArtLibrary, PortraitView, HUD.medallion | Medium |
| 7 | Add an optional restrained super vignette/empire seal and an Echo mist reveal | FightScene.showSuperCutIn + Effects | Medium |

The current strengths to preserve are the painted portraits, coherent gold/ink typography, fixed-tick fight rules, parallax fallback stages, and separate world-space VFX and screen-space HUD. Prefer solving composition and readability before adding more particles. Expansion acceptance should include representative small-phone and iPad captures, maximum camera travel, overlapping supers, and Reduce Motion.
