# Clash app icon

Generated October 8, 2026 using the Aetheria Rising `resources/icon.png` as the material and composition reference and Clash's previous crossed-sword icon as the emblem reference.

`clash-icon-master.png` is the original generated artwork. The composition uses crossed ivory-silver swords, engraved gold fittings, a sculpted gold laurel wreath, and opaque crimson marble. No text or rounded corners are baked into the image.

The same 1024 × 1024 sRGB PNG, without an alpha channel, is exported to:

- `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- `docs/marketing/icon-1024.png`
- `site/img/icon.png`

Delivery checks: square dimensions, no alpha channel, matching export hashes, and visual inspection of the generated composition and resized export. The existing asset catalog already references the app export. No Xcode project regeneration is needed.

`swift Tools/make-icon.swift` regenerates the older procedural icon and overwrites the app and marketing exports. Use it only when deliberately restoring that fallback. `Tools/import-art.swift` currently updates only the app icon. Keep all three exports synchronized when replacing this artwork.

The launch mark remains a separate transparent emblem. Creating a matching transparent launch mark is a follow-up art opportunity documented in `docs/visual-review-2026-10-08.md`.
