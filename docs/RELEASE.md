# Releasing to the App Store

## Before the first upload

1. **App ID and signing.** The project signs automatically with team
   `MZ3635323W` and bundle ID `com.thinkhale.aetheria.clash`. Open the project
   in Xcode, select the AetheriaClash target, Signing & Capabilities, and let
   Xcode register the App ID (or create it at developer.apple.com). No
   capabilities are needed.
2. **App Store Connect record.** New App → iOS, name *Aetheria Clash*
   (or *Aetheria Rising: Clash* if the full title is taken), primary language
   English (U.S.), bundle ID above, SKU `aetheria-clash`.
3. **Privacy.** App Privacy → *Data Not Collected*. Privacy policy URL:
   https://thinkhale.github.io/BattlesOfAetheria/privacy.html (from `site/`,
   deployed by the Website workflow). The
   bundle carries `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, system boot
   time 35F9.1, no tracking).
4. **Export compliance.** `ITSAppUsesNonExemptEncryption` is `NO`; no
   questions at upload.
5. **Age rating.** Cartoon or Fantasy Violence: *Infrequent/Mild* (stylised,
   bloodless combat). Everything else *None*. Expected rating 9+.

## Each release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`, run
   `xcodegen generate`.
2. `cd Packages/FightCore && swift test` (includes the balance round-robin).
3. Run the UI tests on an iPhone and an iPad simulator.
4. Play one arcade run on a device with touch, and one fight with a
   controller.
5. Product → Archive (scheme AetheriaClash, Release) → Distribute → App Store
   Connect. Or let Xcode Cloud do it: create a workflow on `main` with the
   AetheriaClash scheme; the generated project is committed, so no
   post-clone script is needed.
6. `./Tools/store-screenshots.sh` for fresh screenshots (iPhone 6.9" and
   iPad 13", landscape) in `docs/marketing/screenshots/`.

## Store listing

**Name:** Aetheria Clash
**Subtitle:** Ancient heroes. One mist.
**Category:** Games › Fighting (secondary: Action)
**Keywords:** fighting,arcade,versus,rome,egypt,persia,han,ancient,history,warriors,combo,controller

**Promotional text:**
Thirteen commanders of Rome, Egypt, Persia and Han, pulled out of their
centuries by the mist. Fight through them all, then fight yourself.

**Description:**
The mist of the Crossing has drawn the commanders of four ancient empires into
Aetheria, and set them against one another.

Choose from thirteen heroes of Aetheria Rising: Gaius Aurelius behind his
scutum, Tahmina loosing arrows as she leaps away, Bardiya marching through
blows that would stop any lesser man, Mei Lin setting seals beneath her
enemies' feet, and more. Each fights in their own way, with a signature
Special and a devastating Crossing Art.

• 13 commanders from Rome, Egypt, Persia and Han China, each with their own
  moves, lines, rival and arcade epilogue
• Arcade, Versus, two-player and Training modes
• Chains, cancels, throws and breaks, armour, counters, juggles and supers
• Four CPU difficulties, from Squire to Legend
• Five battlefields from the Forum to the Crossing
• Touch controls you can resize and move, plus full game controller and
  keyboard support
• No ads, no purchases, no account, no data collected

**What's new (1.0):** The Crossing opens.

**Support URL:** https://thinkhale.github.io/BattlesOfAetheria/support.html
**Marketing URL:** https://thinkhale.github.io/BattlesOfAetheria/

## Screenshots

Upload from `docs/marketing/screenshots/iphone-6.9/` (2868 × 1320) and
`docs/marketing/screenshots/ipad-13/` (2752 × 2064). App Store Connect scales
these for smaller devices. Lead with `01-fight`, then `03-versus`,
`02-select`, `06-echo`.

## Art upgrades after 1.0

Painted fighter sheets and stage paintings from `docs/chatgpt-art-brief.md`
drop in without code changes; ship them as a 1.1 update once a full roster's
sheets are in.
