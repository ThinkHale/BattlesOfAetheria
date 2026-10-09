import SpriteKit
import FightCore

/// A fighter drawn from pre-rendered sprite strips (made in Blender by Tools/render-strips.py). Each strip is one
/// action, frames side by side; `fighter-<hero>.json` gives each strip's frame size, count, where the feet stand,
/// the figure's standing height in pixels, its frame rate, and playback hints: `contact` (the frame where an attack
/// lands), `backward` (the clip travels backwards) and `pingpong` (a loop that plays forward then back).
final class SpriteBody: SKNode {
    struct Strip: Decodable {
        let frames: Int
        let width: Int
        let height: Int
        let anchor: [Double]
        let loop: Bool
        let figureHeight: Double
        let fps: Double?
        let contact: Int?
        let backward: Bool?
        let pingpong: Bool?
    }

    /// One hero's decoded strips, shared by both sides of a mirror match and kept for a rematch.
    private final class Sheets {
        let textures: [String: [SKTexture]]
        let strips: [String: Strip]
        init(textures: [String: [SKTexture]], strips: [String: Strip]) { self.textures = textures; self.strips = strips }
    }
    private static var cache: [HeroID: Sheets] = [:]

    /// Drops cached strips for heroes not in the coming fight (each hero's sheets take ~150 MB once decoded).
    static func keepOnly(_ heroes: Set<HeroID>) {
        cache = cache.filter { heroes.contains($0.key) }
    }

    private let node = SKSpriteNode()
    /// The same frame drawn again additively, for the hit flash (a tint alone only darkens).
    private let glow = SKSpriteNode()
    private let sheets: Sheets
    private var scaleFactor: CGFloat = 1
    /// What is on screen: the state it shows, when it started (in simulation ticks), and the frame.
    private var segment = ""
    private var segmentStart = 0
    private var shownStrip = ""
    private var shownIndex = 0
    /// The strip and frame on screen when the current state began (a KO carries on from a knockdown's fall).
    private var entryStrip = ""
    private var entryIndex = 0

    private init(sheets: Sheets) {
        self.sheets = sheets
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Returns nil when this hero has no sheets bundled (the rig is used).
    static func load(hero: HeroID) -> SpriteBody? {
        let sheets: Sheets
        if let cached = cache[hero] {
            sheets = cached
        } else {
            guard let url = Bundle.main.url(forResource: "fighter-\(hero.rawValue)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let strips = try? JSONDecoder().decode([String: Strip].self, from: data),
                  strips["idle"] != nil else { return nil }
            var textures: [String: [SKTexture]] = [:]
            var decoded: [String: Strip] = [:]
            for (action, strip) in strips {
                // contentsOfFile: UIImage(named:) would keep a second decoded copy in its own cache.
                guard let path = Bundle.main.path(forResource: "fighter-\(hero.rawValue)-\(action)", ofType: "png"),
                      let image = UIImage(contentsOfFile: path) else { continue }
                let sheet = SKTexture(image: image)
                sheet.filteringMode = .linear
                let w = 1 / CGFloat(strip.frames)
                textures[action] = (0..<strip.frames).map { SKTexture(rect: CGRect(x: CGFloat($0) * w, y: 0, width: w, height: 1), in: sheet) }
                decoded[action] = strip
            }
            guard textures["idle"] != nil else { return nil }
            sheets = Sheets(textures: textures, strips: decoded)
            cache[hero] = sheets
            // Upload to the GPU now, during the round intro, rather than on each strip's first use mid-fight.
            SKTexture.preload(textures.values.compactMap(\.first), withCompletionHandler: {})
        }
        let body = SpriteBody(sheets: sheets)
        body.scaleFactor = CGFloat(180 * hero.hero.stats.stature / sheets.strips["idle"]!.figureHeight)
        body.addChild(body.node)
        body.glow.blendMode = .add
        body.glow.colorBlendFactor = 1
        body.glow.alpha = 0
        body.node.addChild(body.glow)
        return body
    }

    private func strip(_ names: String...) -> String {
        names.first { sheets.textures[$0] != nil } ?? "idle"
    }

    /// Shows the fighter as of simulation tick `clock` (the match's frame count).
    func show(_ f: Fighter, clock: Int) {
        let key: String = {
            switch f.action {
            case .idle, .intro: "idle"
            case .guarding, .blockstun: "guard"
            default: "\(f.action)"
            }
        }()
        if key != segment {
            entryStrip = shownStrip; entryIndex = shownIndex
            segment = key; segmentStart = clock
        }
        let elapsed = Double(clock - segmentStart)
        let action: String
        // Either an explicit position through the strip (0...1), or nil to play it in time from the segment's start.
        var progress: Double? = nil
        var reverse = false
        switch f.action {
        case .idle, .intro: action = "idle"
        case .walk:
            action = strip("walk", "idle")
            reverse = f.velocity.x * f.facing < 0                 // stepping back plays the walk backwards
        case let .dash(back):
            action = strip("dash", "walk", "idle")
            // A back-jump clip used as the dash runs forwards for a back-dash and reversed for a forward one.
            reverse = back != (sheets.strips[action]?.backward == true)
        case .guarding, .blockstun: action = strip("guard", "idle")
        case .jumpSquat:
            action = strip("jump", "idle"); progress = 0.12
        case .airborne:
            // By the arc, not the clock: push-off, rise, apex, fall.
            action = strip("jump", "idle")
            let v0 = max(1, f.hero.stats.jumpVelocity)
            progress = 0.25 + 0.45 * min(1, max(0, (v0 - f.velocity.y) / (2 * v0)))
        case .landing:
            action = strip("jump", "idle"); progress = min(0.99, 0.75 + elapsed * 0.04)
        case let .attack(slot):
            let move = f.moves[slot]
            switch slot {
            case .light1: action = strip("light")
            case .light2: action = strip("light2", "light")
            case .light3: action = strip("light3", "heavy", "light")
            case .heavy: action = strip("heavy", "light")
            // Air attacks borrow quick ground swings (a kick for the archers): the jump clip has no strike in it.
            case .airLight: action = strip("light2", "light")
            case .airHeavy: action = strip("light3", "heavy", "light")
            case .throwAttempt: action = strip("throw", "heavy")
            case .special: action = strip("special", "heavy")
            case .superArt: action = strip("super", "special", "heavy")
            }
            progress = attackProgress(f, move: move, strip: sheets.strips[action])
        case .throwHold(attacker: true):
            action = strip("throw", "heavy"); progress = contactFraction(sheets.strips[action])
        case .hitstun:
            // Recoil and recover over exactly the stun: frame/(frame + ticks left).
            action = strip("hit", "idle"); progress = Double(f.frame) / Double(max(1, f.frame + f.stun))
        case .throwHold(attacker: false):
            action = strip("hit", "idle"); progress = 0.35
        case .juggle:
            // Launched: the first part of the fall, by height.
            action = strip("ko", "hit"); progress = min(0.55, Double(f.frame) / 40 * 0.55)
        case .knockdown, .ko:
            action = strip("ko", "hit")
            // Carry on from wherever the fall already is (a juggle or knockdown) instead of standing up to fall again.
            let start = entryStrip == action ? Double(entryIndex) / Double(max(1, frameCount(action) - 1)) : 0
            progress = min(1, start + elapsed / 30)
        case .getUp:
            action = strip("ko", "idle"); progress = Double(f.frame) / 20; reverse = true
        case .victory:
            action = strip("victory", "idle")
        }
        guard let frames = sheets.textures[action], let info = sheets.strips[action] else { return }
        let n = frames.count
        var index: Int
        if let p = progress {
            index = min(n - 1, max(0, Int((p * Double(n)).rounded(.down))))
            if p >= 1 { index = n - 1 }
            if reverse { index = n - 1 - index }
        } else {
            // In time: ticks since this state began at the strip's own rate (slows with the KO slow motion, keeps
            // its speed when the display drops to 30 Hz).
            let fps = max(info.loop ? 5 : 0, info.fps ?? (info.loop ? 10 : 12))
            let i = Int(elapsed * fps / Double(Match.tickRate))
            if info.loop {
                if info.pingpong == true, n > 1 {
                    let period = 2 * (n - 1), k = i % period
                    index = k < n ? k : period - k
                } else {
                    index = i % n
                }
            } else {
                index = min(n - 1, i)
            }
            if reverse { index = n - 1 - index }
        }
        shownStrip = action; shownIndex = index
        node.texture = frames[index]
        node.size = CGSize(width: CGFloat(info.width) * scaleFactor, height: CGFloat(info.height) * scaleFactor)
        node.anchorPoint = CGPoint(x: info.anchor[0], y: 1 - info.anchor[1])
        node.zRotation = 0
        glow.texture = node.texture
        glow.size = node.size
        glow.anchorPoint = node.anchorPoint
    }

    private func frameCount(_ action: String) -> Int { sheets.textures[action]?.count ?? 1 }

    private func contactFraction(_ info: Strip?) -> Double {
        guard let info else { return 0.4 }
        let c = Double(info.contact ?? Int(Double(info.frames) * 0.4))
        return (c + 0.5) / Double(info.frames)
    }

    /// Where an attack strip is at this tick: the wind-up (frames before `contact`) spread over the startup, the blow
    /// on the first active tick, and the follow-through over the rest, so the swing meets the hit and its pause.
    private func attackProgress(_ f: Fighter, move: Move, strip info: Strip?) -> Double {
        guard let info, info.frames > 1 else { return Double(f.frame) / Double(max(1, move.total)) }
        let n = Double(info.frames)
        let contact = Double(info.contact ?? Int(n * 0.4))
        var frame = Double(f.frame)
        var first = Double(move.firstActive)
        // A counter stance holds its guard until struck, then answers from the moment it was hit.
        if move.counterWindow != nil {
            guard let struck = f.counterTriggeredAt else { return min(contact - 1, contact * frame / first) / n }
            frame = Double(f.frame - struck)
            first = 4
        }
        let index: Double
        if frame <= first {
            index = contact * frame / max(1, first)
        } else {
            let rest = max(1, Double(move.total) - first)
            index = contact + (n - 1 - contact) * min(1, (frame - first) / rest)
        }
        return (index + 0.5) / n
    }

    /// Lights the figure for a hit, an armoured blow or a counter.
    func flash(_ color: UIColor?) {
        if let color {
            glow.color = color
            glow.alpha = 0.55
        } else {
            glow.alpha = 0
        }
    }
}
