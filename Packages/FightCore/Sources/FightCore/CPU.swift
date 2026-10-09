public enum Difficulty: Int, CaseIterable, Codable, Sendable, Identifiable {
    case squire, soldier, champion, legend

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .squire: "Squire"
        case .soldier: "Soldier"
        case .champion: "Champion"
        case .legend: "Legend"
        }
    }

    public var blurb: String {
        switch self {
        case .squire: "Learning the ropes. Forgiving and slow to react."
        case .soldier: "A steady opponent who guards and punishes now and then."
        case .champion: "Reads your habits, guards often, finishes combos."
        case .legend: "Reacts like a veteran. Every opening is punished."
        }
    }

    /// Ticks before the CPU sees what its opponent started doing.
    var reaction: Int { [24, 16, 10, 6][rawValue] }
    var guardChance: Double { [0.25, 0.5, 0.74, 0.9][rawValue] }
    var comboChance: Double { [0.3, 0.62, 0.86, 1.0][rawValue] }
    var antiAirChance: Double { [0.15, 0.4, 0.7, 0.9][rawValue] }
    var punishChance: Double { [0.1, 0.35, 0.65, 0.9][rawValue] }
    var throwBreakChance: Double { [0.05, 0.25, 0.5, 0.75][rawValue] }
    var aggression: Double { [0.35, 0.5, 0.6, 0.7][rawValue] }
    var superChance: Double { [0.25, 0.6, 0.9, 1.0][rawValue] }
    /// How often a counter stance answers a blow it sees coming instead of guarding.
    var counterChance: Double { [0.06, 0.15, 0.25, 0.32][rawValue] }
    /// Chance per tick, while zoning, of sending a projectile: gentler on the easier settings, where a stream of
    /// projectiles is the hardest thing for a new player to get through.
    var zoneRate: Double { [0.015, 0.025, 0.04, 0.05][rawValue] }
}

/// A computer opponent. It sees its enemy's moves only after a reaction delay,
/// decides to guard, punish or press its own attack, and presses buttons the
/// way a person would (a press is a tap, released before the next).
public struct CPU: Sendable {
    public let difficulty: Difficulty
    private var rng: SeededRandom
    private var seen: [FoeSnapshot] = []
    private var plan: Plan = .hold
    private var planTicks = 0
    private var lastOutput: Controls = []
    private var guardDecision: (key: Int, guardIt: Bool)? = nil
    private var chainDecision: (key: Int, follow: Bool)? = nil
    private var antiAirDecision: (key: Int, act: Bool)? = nil
    private var throwBreakDecision: (key: Int, at: Int)? = nil
    private var holdGuardTicks = 0
    private var holdDirectionTicks = 0
    private var heldDirection: Controls = []

    private enum Plan { case hold, approach, retreat, zone, pressure, jumpIn, bait }

    private struct FoeSnapshot {
        var action: FighterAction
        var frame: Int
        var position: Vec
        var velocity: Vec
        var actionStart: Int
    }

    public init(difficulty: Difficulty, seed: UInt64) {
        self.difficulty = difficulty
        self.rng = SeededRandom(seed: seed &* 2_654_435_761 &+ 97)
    }

    public mutating func controls(for index: Int, in match: Match) -> Controls {
        let output = decide(index, match)
        // A button pressed last tick must be let go before it can be pressed again.
        var tapped = output
        for button in [Controls.light, .heavy, .special, .superArt, .dash] where lastOutput.contains(button) && output.contains(button) {
            tapped.remove(button)
        }
        lastOutput = tapped
        return tapped
    }

    private mutating func remember(_ foe: Fighter, now: Int) {
        let start = (seen.last.map { $0.action == foe.action ? $0.actionStart : now }) ?? now
        seen.append(FoeSnapshot(action: foe.action, frame: foe.frame, position: foe.position, velocity: foe.velocity, actionStart: start))
        if seen.count > 40 { seen.removeFirst(seen.count - 40) }
    }

    private var perceived: FoeSnapshot? {
        guard !seen.isEmpty else { return nil }
        let index = max(0, seen.count - 1 - difficulty.reaction)
        return seen[index]
    }

    private mutating func decide(_ i: Int, _ match: Match) -> Controls {
        let me = match.fighters[i]
        let foe = match.fighters[1 - i]
        remember(foe, now: match.frameCount)
        guard case .fighting = match.phase else { return [] }

        let forward: Controls = me.facing > 0 ? .right : .left
        let back: Controls = me.facing > 0 ? .left : .right
        let distance = abs(foe.position.x - me.position.x)

        // Caught in a throw: maybe break it.
        if case .throwHold(attacker: false) = me.action {
            let key = match.frameCount - me.frame
            if throwBreakDecision?.key != key {
                let breaks = rng.chance(difficulty.throwBreakChance)
                throwBreakDecision = (key, breaks ? rng.int(2...9) : Int.max)
            }
            if let decision = throwBreakDecision, me.frame >= decision.at { return [.guardButton, .light] }
            return []
        }

        // Keep a combo going.
        if case let .attack(slot) = me.action {
            let move = me.moves[slot]
            guard me.moveConnected, me.frame > move.startup else { return [] }
            let key = match.frameCount - me.frame
            if chainDecision?.key != key { chainDecision = (key, rng.chance(difficulty.comboChance)) }
            guard chainDecision?.follow == true else { return [] }
            if move.cancelsInto.contains(.superArt), me.meter >= 100, rng.chance(difficulty.superChance * 0.25) { return [.superArt] }
            switch slot {
            case .light1: return [.light]
            case .light2: return rng.chance(0.5) ? [.light] : [.heavy]
            case .light3, .heavy: return useSpecialAsFinisher(me) ? [.special] : []
            case .airLight: return [.heavy]
            default: return []
            }
        }

        if case .airborne = me.action {
            // Strike on the way down when close enough.
            if distance < 120 && me.velocity.y < 4 { return rng.chance(0.6) ? [.heavy] : [.light] }
            return []
        }

        guard me.isActionable else {
            // In blockstun keep guarding; otherwise nothing to do.
            if case .blockstun = me.action { return [.guardButton] }
            return []
        }

        let seenFoe = perceived ?? FoeSnapshot(action: foe.action, frame: foe.frame, position: foe.position, velocity: foe.velocity, actionStart: 0)
        let seenDistance = abs(seenFoe.position.x - me.position.x)

        // Projectiles on their way in.
        let incoming = match.projectiles.contains { p in
            guard p.owner != i else { return false }
            let toward = (me.position.x - p.position.x) * p.velocity.x > 0 || p.spec.targetsEnemy || p.spec.kind == .seal
            let near = abs(p.position.x - me.position.x) < (p.spec.kind == .seal ? 90 : 220)
            return toward && near
        }

        // Guard what it has seen coming.
        var threatened = incoming
        if case let .attack(slot) = seenFoe.action {
            let move = foe.moves[slot]
            let reach = move.hitbox.x + move.hitbox.width + 30 + move.motions.reduce(0) { $0 + Double($1.to - $1.from) * abs($1.velocity.x) }
            if seenDistance < reach && seenFoe.frame <= move.lastActive && slot != .throwAttempt { threatened = true }
            // An enemy recovering from a whiff is an opening.
            if seenFoe.frame > move.lastActive, distance < me.moves[.heavy].hitbox.x + me.moves[.heavy].hitbox.width + 10, !foe.moveConnected {
                let key = seenFoe.actionStart
                if antiAirDecision?.key != key { antiAirDecision = (key, rng.chance(difficulty.punishChance)) }
                if antiAirDecision?.act == true { return me.meter >= 100 && rng.chance(difficulty.superChance * 0.5) ? [.superArt] : [.heavy] }
            }
        }
        if threatened {
            let key = seenFoe.actionStart &+ (incoming ? 7919 : 0)
            if guardDecision?.key != key {
                guardDecision = (key, rng.chance(difficulty.guardChance))
                // A counter stance (Shield Wall) catches a blow it sees coming rather than blocking it.
                if !incoming, me.hero.special == .counter, rng.chance(difficulty.counterChance) { return [.special] }
            }
            if guardDecision?.guardIt == true { holdGuardTicks = 10; return [.guardButton] }
        }
        if holdGuardTicks > 0 { holdGuardTicks -= 1; return [.guardButton] }

        // Anti-air an enemy jumping in.
        if case .airborne = seenFoe.action, seenDistance < 190, seenFoe.velocity.x * (me.position.x - seenFoe.position.x) > 0 || seenDistance < 90 {
            let key = seenFoe.actionStart &+ 31
            if antiAirDecision?.key != key { antiAirDecision = (key, rng.chance(difficulty.antiAirChance)) }
            if antiAirDecision?.act == true {
                if foe.position.y > 60 && distance < 110 { return [.heavy] }
            } else if rng.chance(difficulty.guardChance * 0.5) {
                return [.guardButton]
            }
        }

        // Use a full meter.
        if me.meter >= 100, distance < superRange(me), rng.chance(difficulty.superChance * 0.03) { return [.superArt] }

        // Specials that are neither projectiles nor finishers, used when they make sense.
        switch me.hero.special {
        case .imperialResolve:
            // Steady herself (heal and empower) with room to do it: at range, or with the enemy down.
            let room = distance > 230 || foe.action == .knockdown || foe.action == .getUp
            if room, me.condition(.empowered) == 0, rng.chance(me.healthFraction < 0.6 ? 0.03 : 0.012) { return [.special] }
        case .counter:
            // Set the stance against an enemy walking or dashing into reach.
            let closing = (foe.position.x - me.position.x) * foe.velocity.x < 0
            if closing, distance < 150, rng.chance(difficulty.counterChance * 0.06) { return [.special] }
        case .partingShot:
            // An escape with an arrow in it: leap back from an enemy who has closed in.
            if distance < 140, rng.chance(0.012 + 0.01 * Double(difficulty.rawValue)) { return [.special] }
        default: break
        }

        // An archer pressed close slips away; one being approached backs off
        // before it gets that far.
        let wall = abs(me.position.x) > Match.stageHalfWidth - 90 && (me.position.x > 0) == (me.facing < 0)
        if me.hero.archetype == .archer, !wall {
            let closing = (foe.position.x - me.position.x) * foe.velocity.x < 0
            if distance < 130, rng.chance(0.05 + difficulty.aggression * 0.03) { return rng.chance(0.6) ? [.dash, back] : [.up, back] }
            if closing, distance < 260, rng.chance(0.04 + difficulty.aggression * 0.02) { return [.dash, back] }
        }

        // Up close: strike, throw or guard.
        if distance < 96 {
            let roll = rng.unit()
            if foe.action == .guarding || foe.action == .blockstun, roll < 0.35 { return [.guardButton, .light] }
            if roll < 0.06 * (1 + difficulty.aggression) { return [.light] }
            if roll < 0.075 * (1 + difficulty.aggression) { return [.heavy] }
            if roll < 0.085 + difficulty.aggression * 0.01 { return [.guardButton, .light] }
            if roll < 0.10 { return [back] }
        }

        // Neutral: pick a plan every so often.
        planTicks -= 1
        if planTicks <= 0 { choosePlan(me, foe, distance) }

        switch plan {
        case .hold:
            return rng.chance(0.02) ? [.guardButton] : []
        case .approach:
            if distance > 280, rng.chance(0.02) { return [.dash, forward] }
            if distance < me.moves[.heavy].hitbox.width + 20, rng.chance(0.08 * (1 + difficulty.aggression)) { return [.heavy] }
            return walk(forward)
        case .retreat:
            if distance < 160, rng.chance(0.03) { return [.dash, back] }
            if me.position.x * me.facing < -Match.stageHalfWidth + 80 { plan = .pressure; return [] }
            return walk(back)
        case .zone:
            if specialIsRanged(me), rng.chance(difficulty.zoneRate), !match.projectiles.contains(where: { $0.owner == i && $0.spec.priority > 0 }) {
                return [.special]
            }
            if distance < 220 { return walk(back) }
            if distance > 460 { return walk(forward) }
            return []
        case .pressure:
            if distance > 110 { return walk(forward) }
            if rng.chance(0.1) { return [.light] }
            if rng.chance(0.04) { return useSpecialAsFinisher(me) ? [.special] : [.heavy] }
            return []
        case .jumpIn:
            plan = .hold; planTicks = 20
            return [.up, forward]
        case .bait:
            if distance < 200 { return walk(back) }
            return rng.chance(0.03) ? [.special] : []
        }
    }

    private mutating func walk(_ direction: Controls) -> Controls { direction }

    private mutating func choosePlan(_ me: Fighter, _ foe: Fighter, _ distance: Double) {
        planTicks = rng.int(18...48)
        let aggression = difficulty.aggression
        let roll = rng.unit()
        switch me.hero.archetype {
        case .archer:
            if distance < 160 { plan = roll < 0.45 ? .retreat : roll < 0.75 ? .pressure : .jumpIn }
            else { plan = roll < 0.6 ? .zone : roll < 0.8 ? .hold : .approach }
        case .rider:
            if distance > 300 { plan = roll < 0.35 && specialIsRanged(me) ? .zone : roll < 0.8 ? .approach : .jumpIn }
            else { plan = roll < aggression ? .pressure : roll < aggression + 0.15 ? .jumpIn : roll < 0.85 ? .approach : .bait }
        case .guardian:
            if distance > 260 { plan = roll < 0.7 ? .approach : roll < 0.85 ? .zone : .hold }
            else { plan = roll < aggression ? .pressure : roll < aggression + 0.1 ? .jumpIn : .hold }
        }
        if plan == .jumpIn && rng.chance(0.5) { plan = .approach }
    }

    private func specialIsRanged(_ me: Fighter) -> Bool {
        switch me.hero.special {
        case .volley, .eyeOfHorus, .sunlitVolley, .stratagem, .levy, .partingShot: true
        default: false
        }
    }

    private func useSpecialAsFinisher(_ me: Fighter) -> Bool {
        switch me.hero.special {
        case .imperialResolve, .counter, .stratagem, .eyeOfHorus, .sunlitVolley: false
        default: true
        }
    }

    private func superRange(_ me: Fighter) -> Double {
        me.hero.archetype == .archer ? 600 : me.hero.archetype == .rider ? 500 : 160
    }
}
