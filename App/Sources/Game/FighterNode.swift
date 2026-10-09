import SpriteKit
import FightCore

/// One fighter on stage. Draws them from the rendered sprite strips when the
/// bundle has them (see docs/3d-fighter-pipeline.md) and with the jointed vector
/// rig otherwise, posed from the simulation every tick.
final class FighterNode: SKNode {
    let heroID: HeroID
    private let rig: FighterRig?
    private let sprite: SpriteBody?
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 96, height: 16))
    private let library: PoseLibrary
    private var current: Pose
    private var lastAction: FighterAction = .intro
    private var flashFrames = 0
    private var flashColor: UIColor = .white
    private var tick = 0

    init(hero: HeroID, look: HeroLook, echo: Bool) {
        self.heroID = hero
        let h = hero.hero
        library = PoseLibrary(style: look.weapon, archetype: h.archetype, special: h.special)
        current = library.stance
        if !echo, let sheets = SpriteBody.load(hero: hero) {
            sprite = sheets
            rig = nil
        } else {
            // Painted pieces when the hero has them (never for the mist-made Echo).
            rig = FighterRig(look: look, stature: h.stats.stature, parts: echo ? nil : PaintedParts.load(hero: hero))
            sprite = nil
        }
        super.init()
        shadow.fillColor = UIColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.zPosition = -50
        addChild(shadow)
        if let rig { addChild(rig) }
        if let sprite { addChild(sprite) }
        if echo {
            rig?.alpha = 0.92
            let mist = SKEmitterNode.mist(color: look.energy)
            mist.position = CGPoint(x: 0, y: 90)
            mist.zPosition = -10
            addChild(mist)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func hitFlash(_ color: UIColor = .white, frames: Int = 3) {
        flashFrames = frames
        flashColor = color
    }

    /// `clock` is the simulation tick (the match's frame count) the fighter is shown at.
    func update(_ f: Fighter, clock: Int) {
        tick += 1
        position = CGPoint(x: f.position.x, y: f.position.y)
        let facing = CGFloat(f.facing)
        rig?.xScale = facing
        sprite?.xScale = facing
        // The shadow stays on the ground and shrinks with height.
        shadow.position = CGPoint(x: 0, y: -f.position.y + 2)
        let lift = CGFloat(min(1, f.position.y / 260))
        shadow.setScale(1 - lift * 0.5)
        shadow.alpha = 1 - lift * 0.6

        if let sprite {
            sprite.show(f, clock: clock)
        } else if let rig {
            let target = pose(for: f)
            // Attacks and blows snap; everything else blends in.
            let snappy: Bool = {
                switch f.action {
                case .attack, .hitstun, .blockstun, .juggle, .throwHold: return true
                default: return false
                }
            }()
            let changed = f.action != lastAction
            current = Pose.lerp(current, target, snappy ? (changed ? 0.75 : 1) : (changed ? 0.35 : 0.6))
            rig.apply(current, velocity: CGFloat(f.velocity.x) * facing)
        }
        lastAction = f.action

        if flashFrames > 0 {
            flashFrames -= 1
            rig?.flash(flashColor, amount: flashFrames > 0 ? 0.75 : 0)
            sprite?.flash(flashFrames > 0 ? flashColor : nil)
        }
        // Flicker while invulnerable getting up.
        alpha = f.invulnerable > 0 && tick % 4 < 2 ? 0.6 : 1
    }

    private func pose(for f: Fighter) -> Pose {
        switch f.action {
        case .idle: return library.idle(tick)
        case .walk: return library.walk(tick, forward: f.velocity.x * f.facing > 0)
        case .guarding: return library.guardPose
        case .jumpSquat, .landing: return library.crouch
        case .airborne: return library.air(rising: f.velocity.y > 0)
        case let .dash(back): return library.dash(f.frame, back: back)
        case let .attack(slot):
            return library.attack(f.moves[slot], frame: f.frame, connected: f.moveConnected, counterStruck: f.counterTriggeredAt, airborne: !f.grounded)
        case .blockstun: return library.blockstun(f.frame)
        case .hitstun: return library.hitstun(f.frame, heavy: f.stun > 22)
        case .juggle: return library.juggle(f.frame, rising: f.velocity.y > 0)
        case .knockdown, .ko: return library.lyingDown
        case .getUp: return library.getUp(f.frame, of: 20)
        case let .throwHold(attacker):
            if attacker { return library.attack(f.moves[.throwAttempt], frame: 6, connected: true, counterStruck: nil, airborne: false) }
            return library.thrown(f.frame)
        case .victory: return library.victory(f.frame)
        case .intro: return library.intro(tick)
        }
    }

    var weaponTip: CGPoint { rig?.weaponTipPosition ?? CGPoint(x: position.x, y: position.y + 120) }
}

extension SKEmitterNode {
    /// Slow drifting mist, for the Echo and the Crossing stage.
    static func mist(color: UIColor, rate: CGFloat = 14, spread: CGFloat = 80) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.softDot
        e.particleBirthRate = rate
        e.particleLifetime = 2.6
        e.particleLifetimeRange = 1
        e.particlePositionRange = CGVector(dx: spread, dy: 150)
        e.particleSpeed = 14
        e.particleSpeedRange = 10
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi
        e.particleAlpha = 0.35
        e.particleAlphaRange = 0.15
        e.particleAlphaSpeed = -0.12
        e.particleScale = 0.9
        e.particleScaleRange = 0.5
        e.particleScaleSpeed = 0.3
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        return e
    }
}

/// Textures drawn once in code.
@MainActor
enum Textures {
    static let softDot: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        return SKTexture(image: image)
    }()

    static let spark: SKTexture = {
        let size = CGSize(width: 32, height: 8)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
            ctx.cgContext.addEllipse(in: CGRect(origin: .zero, size: size))
            ctx.cgContext.clip()
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 32, y: 0), options: [])
        }
        return SKTexture(image: image)
    }()
}
