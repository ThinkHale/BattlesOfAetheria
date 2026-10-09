# Aetheria Rising: Clash of the Crossing

[![CI](https://github.com/ThinkHale/BattlesOfAetheria/actions/workflows/ci.yml/badge.svg)](https://github.com/ThinkHale/BattlesOfAetheria/actions/workflows/ci.yml)

A 2D fighting game for iPhone and iPad set in the world of
[Aetheria Rising](https://github.com/ThinkHale/aetheria.rising). The thirteen
commanders of Aetheria (Romans, Egyptians, Persians and Han, drawn out of
their own centuries by the mist of the Crossing) fight one another, and at the
end of arcade the mist itself takes the player's face.

Website: https://thinkhale.github.io/BattlesOfAetheria/ (source in `site/`,
deployed by GitHub Pages on every push that touches it).

Native Swift: SpriteKit for the fight, SwiftUI for the menus, no third-party
dependencies, no network, no data collection.

## What's in it

- **13 playable commanders** from the Aetheria Rising hero catalog, each with
  their class (guardian, rider, archer), signature skill as a Special, a
  Crossing Art super, their lore quote, intro, victory and defeat lines, a
  rival, and an arcade epilogue in their own voice.
- **Modes:** Arcade (six opponents with your rival second to last, then the
  Echo of the Crossing; score, continues, resume a run), Versus CPU, Two
  Players (touch plus a controller, or two controllers), Training (dummy
  behaviours, hitbox view, move list).
- **Fighting system:** light chains, heavies, cancels into specials and
  supers, guard, throws and throw breaks, armour, counter stances, juggles
  with a limit, counter hits, combo damage scaling, projectile clashes,
  conditions (empowered, fortified, marked, slowed), meter, 99-second rounds,
  best of three with sudden death. Runs at a fixed 60 ticks a second and is
  deterministic from a seed.
- **CPU** in four difficulties that reacts after a human-like delay, guards,
  punishes whiffs, anti-airs, breaks throws and plays to its class.
- **Five stages** (the Forum, the Nile, Persepolis, the Juyan watchtower, the
  Crossing) drawn in parallax layers, each replaceable by painted art.
- **Controls:** a floating touch stick and buttons (size, opacity and side
  adjustable), MFi/Xbox/PlayStation controllers, and hardware keyboards.
- **Presentation:** the painted hero portraits from Aetheria Rising in menus,
  the HUD and super cut-ins; the strategy game's music; synthesized combat
  sound; haptics; screen shake (can be turned off).

## Layout

```
Packages/FightCore/      the fight: rules, roster, frame data, CPU, arcade (pure Swift, tested on macOS)
App/Sources/Game/        SpriteKit: scene, fighter rigs and sprite strips, stages, HUD, controls, effects
App/Sources/UI/          SwiftUI menus
App/Sources/Services/    audio, haptics, saved profile, art lookup
App/Resources/           portraits, backdrops, music, sounds, fonts, asset catalog
Tools/                   art and audio import, icon, screenshots
docs/                    ChatGPT art brief, design notes, release checklist
```

## Building

Requires Xcode 16 or later (built with Xcode 27) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml`.

```sh
xcodegen generate          # only after editing project.yml or adding resources
open AetheriaClash.xcodeproj
```

Tests:

```sh
cd Packages/FightCore && swift test     # rules, CPU, arcade, round-robin balance
xcodebuild -scheme AetheriaClash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test   # + UI tests
```

## Art from ChatGPT

Every hero is drawn by a jointed vector rig until painted sprite sheets
arrive, and every stage is drawn in code until paintings arrive. To replace
them, give ChatGPT `docs/chatgpt-art-brief.md` and the hero portraits, drop
the results in `art-inbox/`, and run:

```sh
swift Tools/import-art.swift
```

It cuts and aligns the sheets, writes the strips the game plays, copies stage
layers and the icon, and regenerates the Xcode project. Heroes and stages
switch over one at a time as their art lands.

## Shared assets

`Tools/import-reference-art.sh` copies portraits, chronicle paintings and
music from a checkout of `aetheria.rising` next to this repo.
`swift Tools/make-sfx.swift` regenerates the combat sounds and
`swift Tools/make-icon.swift` the drawn icon.

## Launch routes

For screenshots and UI tests, `AETHERIA_START` opens a screen directly:
`menu`, `select`, `hall`, `settings`, `hero:<id>`, `ladder:<id>:<rung>`,
`versus:<id>:<id>`, `results:<id>:<id>`, `ending:<id>`,
`fight:<id>:<id>:<stage>[:demo][:boss]` and `spar:<id>:<id>:<stage>`.

See `docs/RELEASE.md` for shipping to the App Store.
