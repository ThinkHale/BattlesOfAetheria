// Frame data. The match runs at 60 ticks a second; every number of frames
// below is a tick. A move has startup (before it can hit), active frames (when
// its hitbox is out) and recovery (after, when its owner can be punished).

public enum MoveSlot: String, CaseIterable, Codable, Sendable {
    case light1, light2, light3, heavy, airLight, airHeavy, throwAttempt, special, superArt

    public var isAerial: Bool { self == .airLight || self == .airHeavy }
}

/// How hard a blow lands, for hitstop, sound and screen shake.
public enum Impact: Int, Codable, Comparable, Sendable {
    case light, medium, heavy, crushing
    public static func < (a: Impact, b: Impact) -> Bool { a.rawValue < b.rawValue }
}

/// Lasting effects a move or projectile can leave on a fighter.
public enum Condition: String, Codable, Sendable {
    /// Deals more damage.
    case empowered
    /// Takes less damage.
    case fortified
    /// Takes more damage (Eye of Horus).
    case marked
    /// Moves slower (Desert Wind).
    case dusted
}

public struct ConditionGrant: Equatable, Codable, Sendable {
    public var condition: Condition
    public var frames: Int
    public var magnitude: Double
}

public enum ProjectileKind: String, Codable, Sendable {
    case bolt, arrow, fallingArrow, orb, dust, cavalry, seal, sunbeam, wave
}

public struct ProjectileSpec: Equatable, Codable, Sendable {
    public var kind: ProjectileKind
    /// Spawn point relative to the owner's feet, facing right.
    public var origin: Vec
    public var velocity: Vec
    public var gravity: Double = 0
    public var box: LocalBox
    public var damage: Double
    public var hitstun: Int
    public var blockstun: Int
    public var knockback: Vec
    public var lifetime: Int
    /// Frames before it can hit (a seal waits, falling arrows drop first).
    public var armingDelay: Int = 0
    /// Hits it can deal before it is spent; frames between hits.
    public var hits: Int = 1
    public var hitInterval: Int = 12
    public var launches: Bool = false
    public var knocksDown: Bool = false
    public var onHit: ConditionGrant? = nil
    /// Lands where the enemy stands rather than at the origin (falling volley).
    public var targetsEnemy: Bool = false
    /// Spawned from behind the owner's side of the screen (the levy rider).
    public var fromBehind: Bool = false
    /// Strong projectiles pass through weaker ones.
    public var priority: Int = 1
    public var impact: Impact = .medium
}

/// What a move does to its owner while it runs, frame by frame.
public struct Motion: Equatable, Codable, Sendable {
    public var from: Int
    public var to: Int
    /// Forward and upward speed in points per tick.
    public var velocity: Vec
}

public struct Move: Equatable, Sendable {
    public var slot: MoveSlot
    public var name: String
    public var startup: Int
    public var active: Int
    public var recovery: Int
    public var damage: Double
    public var hitstun: Int
    public var blockstun: Int
    public var hitbox: LocalBox
    public var knockback: Vec
    public var impact: Impact
    public var launches: Bool = false
    public var knocksDown: Bool = false
    public var unblockable: Bool = false
    /// Separate hits during the active window, evenly spaced.
    public var hits: Int = 1
    /// Share of damage still dealt through a guard.
    public var chip: Double = 0
    /// Slots this move may be cancelled into once it has connected.
    public var cancelsInto: Set<MoveSlot> = []
    public var motions: [Motion] = []
    /// Frames on which the owner cannot be hit at all.
    public var invulnerable: ClosedRange<Int>? = nil
    /// Frames on which the owner takes hits without flinching, and how many.
    public var armor: ClosedRange<Int>? = nil
    public var armorHits: Int = 0
    /// Frames on which a blow that lands is caught and answered.
    public var counterWindow: ClosedRange<Int>? = nil
    public var projectiles: [(frame: Int, spec: ProjectileSpec)] = []
    public var selfGrant: (frame: Int, grant: ConditionGrant, heal: Double)? = nil
    public var onHitGrant: ConditionGrant? = nil
    /// Passes through the enemy (ignores pushboxes) while active.
    public var passesThrough: Bool = false
    public var meterCost: Double = 0
    /// Ends the move on landing (aerials).
    public var endsOnLanding: Bool = false

    public var total: Int { startup + active + recovery }
    public var firstActive: Int { startup + 1 }
    public var lastActive: Int { startup + active }

    public static func == (a: Move, b: Move) -> Bool { a.slot == b.slot && a.name == b.name }
}

public struct MoveSet: Sendable {
    public var moves: [MoveSlot: Move]
    public subscript(slot: MoveSlot) -> Move { moves[slot]! }

    public static func forHero(_ hero: Hero) -> MoveSet {
        var m: [MoveSlot: Move] = [:]
        let r = hero.stats.reach
        let s = hero.stats.stature
        let archetype = hero.archetype

        // Normals share a skeleton across the roster and are shaped by class.
        let lightReach: Double = archetype == .rider ? 74 : archetype == .guardian ? 68 : 64
        m[.light1] = Move(slot: .light1, name: "Jab", startup: 5, active: 3, recovery: 9, damage: 34,
                          hitstun: 16, blockstun: 11, hitbox: LocalBox(x: 18, y: 104 * s, width: lightReach * r, height: 34),
                          knockback: Vec(2.2, 0), impact: .light, cancelsInto: [.light2, .heavy, .special, .superArt])
        m[.light2] = Move(slot: .light2, name: "Follow", startup: 6, active: 3, recovery: 10, damage: 36,
                          hitstun: 17, blockstun: 11, hitbox: LocalBox(x: 18, y: 86 * s, width: (lightReach + 6) * r, height: 40),
                          knockback: Vec(2.6, 0), impact: .light, cancelsInto: [.light3, .heavy, .special, .superArt],
                          motions: [Motion(from: 1, to: 6, velocity: Vec(1.6, 0))])
        m[.light3] = Move(slot: .light3, name: "Finisher", startup: 9, active: 4, recovery: 16, damage: 58,
                          hitstun: 24, blockstun: 14, hitbox: LocalBox(x: 16, y: 70 * s, width: (lightReach + 18) * r, height: 54),
                          knockback: Vec(7.5, 0), impact: .medium, cancelsInto: [.special, .superArt],
                          motions: [Motion(from: 1, to: 9, velocity: Vec(2.4, 0))])
        let heavyReach: Double = archetype == .guardian ? 98 : archetype == .rider ? 104 : 90
        m[.heavy] = Move(slot: .heavy, name: "Heavy", startup: 12, active: 4, recovery: 19, damage: 88,
                         hitstun: 26, blockstun: 16, hitbox: LocalBox(x: 20, y: 64 * s, width: heavyReach * r, height: 64),
                         knockback: Vec(6.5, 0), impact: .heavy, chip: 0.04, cancelsInto: [.special, .superArt],
                         motions: [Motion(from: 4, to: 12, velocity: Vec(2.8, 0))])
        m[.airLight] = Move(slot: .airLight, name: "Air Strike", startup: 5, active: 8, recovery: 8, damage: 44,
                            hitstun: 18, blockstun: 12, hitbox: LocalBox(x: 6, y: 30 * s, width: 66 * r, height: 60),
                            knockback: Vec(2.5, 0), impact: .light, cancelsInto: [.airHeavy], endsOnLanding: true)
        m[.airHeavy] = Move(slot: .airHeavy, name: "Diving Blow", startup: 8, active: 8, recovery: 12, damage: 78,
                            hitstun: 24, blockstun: 16, hitbox: LocalBox(x: 0, y: 4, width: 82 * r, height: 74),
                            knockback: Vec(4, 0), impact: .heavy, endsOnLanding: true)
        m[.throwAttempt] = Move(slot: .throwAttempt, name: "Throw", startup: 5, active: 2, recovery: 26, damage: 112,
                                hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 10, y: 40, width: 54, height: 100),
                                knockback: Vec(9, 9), impact: .heavy, knocksDown: true, unblockable: true)

        m[.special] = special(hero)
        m[.superArt] = superArt(hero)
        return MoveSet(moves: m)
    }

    // MARK: Specials

    private static func special(_ hero: Hero) -> Move {
        let s = hero.stats.stature
        let name = hero.specialName
        switch hero.special {
        case .counter:
            return Move(slot: .special, name: name, startup: 4, active: 26, recovery: 14, damage: 120,
                        hitstun: 30, blockstun: 0, hitbox: LocalBox(x: 0, y: 30, width: 110, height: 140),
                        knockback: Vec(10, 8), impact: .heavy, knocksDown: true, counterWindow: 4...30)
        case .volley:
            let bolt = ProjectileSpec(kind: .bolt, origin: Vec(52, 112 * s), velocity: Vec(15, 0), box: LocalBox(x: -18, y: -6, width: 36, height: 12),
                                      damage: 54, hitstun: 18, blockstun: 12, knockback: Vec(3, 0), lifetime: 80, impact: .light)
            return Move(slot: .special, name: name, startup: 11, active: 9, recovery: 16, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .light, chip: 0.1,
                        projectiles: [(11, bolt), (19, bolt)])
        case .partingShot:
            var arrow = ProjectileSpec(kind: .arrow, origin: Vec(40, 120 * s), velocity: Vec(14, 0), box: LocalBox(x: -20, y: -6, width: 40, height: 12),
                                       damage: 76, hitstun: 22, blockstun: 14, knockback: Vec(4, 0), lifetime: 70, impact: .medium)
            arrow.priority = 1
            return Move(slot: .special, name: name, startup: 8, active: 6, recovery: 13, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .medium, chip: 0.1,
                        motions: [Motion(from: 1, to: 20, velocity: Vec(-7.5, 0))],
                        invulnerable: 1...6, projectiles: [(12, arrow)])
        case .flankingCharge:
            return Move(slot: .special, name: name, startup: 10, active: 18, recovery: 20, damage: 92,
                        hitstun: 30, blockstun: 14, hitbox: LocalBox(x: -10, y: 30, width: 90, height: 120),
                        knockback: Vec(8, 9), impact: .heavy, launches: true, chip: 0.1,
                        motions: [Motion(from: 8, to: 28, velocity: Vec(16, 0))],
                        passesThrough: true)
        case .desertWind:
            let dust = ProjectileSpec(kind: .dust, origin: Vec(-30, 0), velocity: .zero, box: LocalBox(x: -80, y: 0, width: 160, height: 120),
                                      damage: 24, hitstun: 6, blockstun: 4, knockback: .zero, lifetime: 150, armingDelay: 6, hits: 3, hitInterval: 40,
                                      onHit: ConditionGrant(condition: .dusted, frames: 150, magnitude: 0.45), priority: 0, impact: .light)
            return Move(slot: .special, name: name, startup: 7, active: 14, recovery: 14, damage: 62,
                        hitstun: 22, blockstun: 12, hitbox: LocalBox(x: 0, y: 40, width: 80, height: 90),
                        knockback: Vec(5, 0), impact: .medium, chip: 0.08,
                        motions: [Motion(from: 4, to: 20, velocity: Vec(14, 0))],
                        projectiles: [(5, dust)], onHitGrant: ConditionGrant(condition: .dusted, frames: 150, magnitude: 0.45))
        case .armoredAdvance:
            return Move(slot: .special, name: name, startup: 22, active: 6, recovery: 24, damage: 118,
                        hitstun: 34, blockstun: 20, hitbox: LocalBox(x: 20, y: 70 * s, width: 128, height: 50),
                        knockback: Vec(12, 0), impact: .crushing, knocksDown: true, chip: 0.12,
                        motions: [Motion(from: 1, to: 22, velocity: Vec(3.8, 0))],
                        armor: 1...24, armorHits: 1)
        case .ironFormation:
            return Move(slot: .special, name: name, startup: 16, active: 6, recovery: 18, damage: 62,
                        hitstun: 26, blockstun: 16, hitbox: LocalBox(x: -40, y: 0, width: 150, height: 120),
                        knockback: Vec(9, 4), impact: .heavy, chip: 0.1,
                        armor: 1...12, armorHits: 1,
                        selfGrant: (16, ConditionGrant(condition: .fortified, frames: 240, magnitude: 0.2), 0))
        case .eyeOfHorus:
            let orb = ProjectileSpec(kind: .orb, origin: Vec(56, 110 * s), velocity: Vec(7.4, 0), box: LocalBox(x: -24, y: -24, width: 48, height: 48),
                                     damage: 56, hitstun: 26, blockstun: 16, knockback: Vec(3, 0), lifetime: 170,
                                     onHit: ConditionGrant(condition: .marked, frames: 300, magnitude: 0.25), priority: 2, impact: .medium)
            return Move(slot: .special, name: name, startup: 14, active: 4, recovery: 17, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .medium, chip: 0.1, projectiles: [(14, orb)])
        case .levy:
            let rider = ProjectileSpec(kind: .cavalry, origin: Vec(-200, 0), velocity: Vec(13, 0), box: LocalBox(x: -60, y: 0, width: 120, height: 150),
                                       damage: 96, hitstun: 30, blockstun: 18, knockback: Vec(8, 10), lifetime: 110, launches: true,
                                       fromBehind: true, priority: 3, impact: .heavy)
            return Move(slot: .special, name: name, startup: 18, active: 4, recovery: 26, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .heavy, chip: 0.1, projectiles: [(18, rider)])
        case .imperialResolve:
            return Move(slot: .special, name: name, startup: 28, active: 2, recovery: 18, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .medium,
                        selfGrant: (28, ConditionGrant(condition: .empowered, frames: 360, magnitude: 0.2), 70))
        case .sunlitVolley:
            let falling = ProjectileSpec(kind: .fallingArrow, origin: Vec(0, 420), velocity: Vec(0, -13), box: LocalBox(x: -26, y: -40, width: 52, height: 80),
                                         damage: 46, hitstun: 22, blockstun: 12, knockback: Vec(2, 0), lifetime: 60, armingDelay: 0,
                                         targetsEnemy: true, impact: .light)
            return Move(slot: .special, name: name, startup: 12, active: 4, recovery: 18, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .medium, chip: 0.1,
                        projectiles: [(20, falling), (25, falling), (30, falling)])
        case .royalCharge:
            return Move(slot: .special, name: name, startup: 14, active: 16, recovery: 24, damage: 100,
                        hitstun: 34, blockstun: 16, hitbox: LocalBox(x: 10, y: 20, width: 100, height: 130),
                        knockback: Vec(6, 15), impact: .heavy, launches: true, chip: 0.1,
                        motions: [Motion(from: 10, to: 30, velocity: Vec(14, 0))],
                        armor: 6...24, armorHits: 1)
        case .stratagem:
            let seal = ProjectileSpec(kind: .seal, origin: Vec(190, 0), velocity: .zero, box: LocalBox(x: -60, y: 0, width: 120, height: 140),
                                      damage: 76, hitstun: 30, blockstun: 18, knockback: Vec(4, 14), lifetime: 46, armingDelay: 28,
                                      launches: true, targetsEnemy: true, priority: 3, impact: .heavy)
            let gust = ProjectileSpec(kind: .wave, origin: Vec(50, 100 * s), velocity: Vec(12, 0), box: LocalBox(x: -18, y: -40, width: 36, height: 80),
                                      damage: 34, hitstun: 20, blockstun: 16, knockback: Vec(2, 0), lifetime: 60, impact: .light)
            return Move(slot: .special, name: name, startup: 11, active: 4, recovery: 16, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .medium, chip: 0.12, projectiles: [(11, gust), (12, seal)])
        }
    }

    // MARK: Crossing Arts (supers)

    private static func superArt(_ hero: Hero) -> Move {
        let name = hero.superName
        switch hero.archetype {
        case .guardian:
            // A shielded advance of five blows; invulnerable as it starts.
            return Move(slot: .superArt, name: name, startup: 10, active: 30, recovery: 24, damage: 310,
                        hitstun: 40, blockstun: 24, hitbox: LocalBox(x: 10, y: 10, width: 120, height: 170),
                        knockback: Vec(12, 10), impact: .crushing, knocksDown: true, hits: 5, chip: 0.2,
                        motions: [Motion(from: 8, to: 40, velocity: Vec(6, 0))],
                        invulnerable: 1...16, meterCost: 100)
        case .rider:
            // A full-screen charge.
            return Move(slot: .superArt, name: name, startup: 12, active: 36, recovery: 26, damage: 300,
                        hitstun: 44, blockstun: 22, hitbox: LocalBox(x: -20, y: 0, width: 140, height: 170),
                        knockback: Vec(10, 16), impact: .crushing, launches: true, hits: 4, chip: 0.2,
                        motions: [Motion(from: 10, to: 48, velocity: Vec(19, 0))],
                        invulnerable: 1...18, passesThrough: true, meterCost: 100)
        case .archer:
            // A great shot that crosses the screen and hits several times.
            let beam = ProjectileSpec(kind: .sunbeam, origin: Vec(60, 110 * hero.stats.stature), velocity: Vec(22, 0),
                                      box: LocalBox(x: -90, y: -50, width: 180, height: 100), damage: 300, hitstun: 44, blockstun: 22,
                                      knockback: Vec(10, 12), lifetime: 70, hits: 4, hitInterval: 6, launches: true, priority: 9, impact: .crushing)
            return Move(slot: .superArt, name: name, startup: 14, active: 6, recovery: 30, damage: 0,
                        hitstun: 0, blockstun: 0, hitbox: LocalBox(x: 0, y: 0, width: 0, height: 0),
                        knockback: .zero, impact: .crushing, chip: 0.2, invulnerable: 1...20,
                        projectiles: [(14, beam)], meterCost: 100)
        }
    }
}
