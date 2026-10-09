import SpriteKit
import FightCore

enum FightMode: Equatable {
    case arcade(rung: Int)
    case versusCPU
    case versusLocal
    case training
}

/// Everything needed to start a fight.
struct FightSetup: Equatable {
    var match: MatchConfig
    var mode: FightMode
    /// CPU difficulty for player two; nil when a person plays them.
    var cpu: Difficulty?
    var altPalette: [Bool] = [false, false]
    /// Both sides played by the CPU (attract mode and screenshots).
    var demo = false
}

struct FightResult: Equatable {
    var setup: FightSetup
    var winner: Int
    var stats: [FightStats]
    var healthLeft: [Double]
    var secondsLeft: Int
    var rounds: [Int]
}

enum TrainingDummy: String, CaseIterable, Identifiable {
    case stand = "Stand", guardAll = "Guard", jump = "Jump", cpu = "Fight back"
    var id: String { rawValue }
}

/// The fight: runs the match at a fixed 60 ticks a second, reads touch,
/// controller and keyboard input, and draws everything it does.
final class FightScene: SKScene {
    let setup: FightSetup
    private(set) var match: Match
    private var cpu: CPU?
    private var demoCPU: CPU?
    private let world = SKNode()
    private var stage: StageNode!
    private var fighterNodes: [FighterNode] = []
    private var projectileNodes: [Int: ProjectileNode] = [:]
    private var hud: HUDNode!
    private var controls: TouchControls?
    private let superCurtain = SKSpriteNode(color: .black, size: .zero)
    private let cutIn = SKNode()
    private var hitboxLayer = SKNode()

    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var frontFighter = 0
    private var slowMotion = 0
    private var shake: CGFloat = 0
    private var cameraX: CGFloat = 0
    private var zoom: CGFloat = 1
    private var finished = false
    private var resultDelay = 0
    private var looks: [HeroLook] = []
    private var menuPaused = false
    private var pausePressedLastTick = false

    var settings = Profile.Settings()
    var trainingDummy: TrainingDummy = .stand
    var showHitboxes = false { didSet { hitboxLayer.isHidden = !showHitboxes } }
    var onPause: (() -> Void)?
    var onFinish: ((FightResult) -> Void)?

    init(setup: FightSetup, size: CGSize, settings: Profile.Settings) {
        self.setup = setup
        self.settings = settings
        self.match = Match(config: setup.match)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .black
        if let difficulty = setup.cpu { cpu = CPU(difficulty: difficulty, seed: setup.match.seed &+ 11) }
        if setup.demo { demoCPU = CPU(difficulty: .champion, seed: setup.match.seed &+ 23) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Setup

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        guard stage == nil else { return }
        // SwiftUI may not have measured the view when the scene was made.
        if view.bounds.width > 0 { size = view.bounds.size }
        addChild(world)
        SpriteBody.keepOnly(Set(setup.match.heroes))
        stage = StageNode(stage: setup.match.stage)
        world.addChild(stage)

        for i in 0..<2 {
            let hero = setup.match.heroes[i]
            let echo = setup.match.bosses.contains(i)
            var look = echo ? HeroLook.echo(of: hero) : HeroLook.of(hero, alt: setup.altPalette[i])
            // A mirror match: the second fighter wears the other palette.
            if i == 1, !echo, setup.match.heroes[0] == hero, setup.altPalette[0] == setup.altPalette[1] {
                look = HeroLook.of(hero, alt: !setup.altPalette[0])
            }
            looks.append(look)
            let node = FighterNode(hero: hero, look: look, echo: echo)
            node.zPosition = CGFloat(10 + i)
            world.addChild(node)
            fighterNodes.append(node)
        }
        world.addChild(hitboxLayer)
        hitboxLayer.zPosition = 500
        hitboxLayer.isHidden = !showHitboxes

        let safe = view.safeAreaInsets
        let names = setup.match.heroes.enumerated().map { setup.match.bosses.contains($0.offset) ? "The Echo" : $0.element.hero.name }
        hud = HUDNode(size: size, safe: safe, heroes: setup.match.heroes, names: names, echoes: setup.match.bosses, roundsToWin: setup.match.roundsToWin, training: setup.mode == .training)
        addChild(hud)

        controls = TouchControls(size: size, safe: safe, swap: settings.swapControls, scale: CGFloat(settings.controlsScale),
                                 opacity: CGFloat(settings.controlsOpacity), showHints: settings.showInputHints)
        controls?.onPause = { [weak self] in self?.requestPause() }
        if let controls { addChild(controls) }
        controls?.setSuperReady(false)

        superCurtain.size = CGSize(width: 4000, height: 4000)
        superCurtain.alpha = 0
        superCurtain.zPosition = 900
        addChild(superCurtain)
        cutIn.zPosition = 950
        addChild(cutIn)

        ControllerInput.shared.onPause = { [weak self] in self?.requestPause() }
        ControllerInput.shared.onChange = { [weak self] in self?.updateControlsVisibility() }
        updateControlsVisibility()

        AudioManager.shared.playMusic(.stage(setup.match.stage))
        AudioManager.shared.duckMusic(false)      // a rematch keeps the track, which the pause menu left ducked
        handle(match.events)
        renderFrame()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        hud?.layout(size: size)
        controls?.layout(size: size)
    }

    private func updateControlsVisibility() {
        // With a pad in hand the touch controls get out of the way.
        controls?.isHidden = setup.demo || (ControllerInput.shared.padInUse && setup.mode != .versusLocal)
    }

    // MARK: Pause

    private func requestPause() {
        guard !menuPaused, !finished else { return }
        onPause?()
    }

    func setPaused(_ value: Bool) {
        menuPaused = value
        isPaused = value
        controls?.reset()
        lastTime = 0
        AudioManager.shared.duckMusic(value)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if ControllerInput.shared.padInUse {
            ControllerInput.shared.padInUse = false
            updateControlsVisibility()
        }
        controls?.touchesBegan(touches, in: self)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { controls?.touchesMoved(touches, in: self) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { controls?.touchesEnded(touches, in: self) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { controls?.touchesEnded(touches, in: self) }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        guard !menuPaused else { return }
        if lastTime == 0 { lastTime = currentTime }
        let dt = min(0.1, currentTime - lastTime)
        lastTime = currentTime
        // Slow motion after a knockout: half speed.
        accumulator += slowMotion > 0 ? dt * 0.4 : dt
        let step = 1.0 / Double(Match.tickRate)
        var ticks = 0
        while accumulator >= step && ticks < 4 {
            accumulator -= step
            ticks += 1
            stepMatch()
        }
        // Draw every display frame, even one without a tick (slow motion runs ticks at 0.4x), so the camera, zoom
        // and shake stay smooth.
        renderFrame()
    }

    private func gatherInputs() -> [Controls] {
        let pads = ControllerInput.shared
        var p1 = pads.keyboardControls()
        if setup.mode != .versusLocal || pads.padCount >= 2 {
            let pad = pads.controls(pad: 0)
            p1.formUnion(pad)
            if !pad.isEmpty, controls?.isHidden == false { updateControlsVisibility() }
        }
        if let controls, !controls.isHidden { p1.formUnion(controls.currentControls(facing: match.fighters[0].facing)) }
        if demoCPU != nil { p1 = demoCPU!.controls(for: 0, in: match) }

        let pausePressed = pads.keyboardPausePressed
        if pausePressed && !pausePressedLastTick { DispatchQueue.main.async { [weak self] in self?.requestPause() } }
        pausePressedLastTick = pausePressed

        var p2: Controls = []
        switch setup.mode {
        case .versusLocal:
            p2 = pads.controls(pad: pads.padCount >= 2 ? 1 : 0)
        case .training:
            switch trainingDummy {
            case .stand: p2 = []
            case .guardAll: p2 = [.guardButton]
            case .jump: p2 = match.frameCount % 70 < 2 ? [.up] : []
            case .cpu: p2 = cpu?.controls(for: 1, in: match) ?? []
            }
        default:
            p2 = cpu?.controls(for: 1, in: match) ?? []
        }
        return [p1, p2]
    }

    private func stepMatch() {
        if slowMotion > 0 { slowMotion -= 1 }
        let inputs = gatherInputs()
        match.tick(inputs)
        handle(match.events)
        swingSounds()
        if match.isOver && !finished {
            resultDelay += 1
            if resultDelay > 150 { finish() }
        }
    }

    /// A blow is heard as it swings, two ticks before it can land (the hit sound follows if it connects). Spears,
    /// lances and the standard thrust; the commander may shout on the big ones.
    private func swingSounds() {
        let audio = AudioManager.shared
        for (i, fighter) in match.fighters.enumerated() {
            guard case let .attack(slot) = fighter.action else { continue }
            let move = fighter.moves[slot]
            guard move.hitbox.width > 0, fighter.frame == max(1, move.firstActive - 2) else { continue }
            let big = [.heavy, .airHeavy, .light3, .special, .superArt].contains(slot)
            let thrust = [.spear, .lance, .standard].contains(looks[i].weapon) && [.light1, .light2, .heavy].contains(slot)
            if thrust, audio.has(.swingThrust) { audio.play(.swingThrust, volume: big ? 1 : 0.8) }
            else { audio.play(big ? .whooshHeavy : .whooshLight, volume: big ? 0.8 : 0.6) }
            if big, Double.random(in: 0...1) < 0.5 { audio.playAny(FighterVoice.of(fighter.hero.id).attacks, volume: 0.75) }
        }
    }

    private func finish() {
        finished = true
        guard case let .matchOver(winner) = match.phase else { return }
        let result = FightResult(setup: setup, winner: winner, stats: match.fighters.map(\.stats),
                                 healthLeft: (0..<2).map { match.healthFraction($0) }, secondsLeft: match.secondsLeft,
                                 rounds: match.fighters.map(\.roundsWon))
        onFinish?(result)
    }

    // MARK: Events

    private func point(_ v: Vec) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    private func handle(_ events: [MatchEvent]) {
        let audio = AudioManager.shared
        for event in events {
            switch event {
            case let .roundAnnounced(round, final):
                audio.play(.gong)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { audio.play(.announce(round: round, final: final)) }
                hud.announce(final ? "FINAL ROUND" : "ROUND \(round)", sub: setup.match.stage.name, hold: 1.2)
                zoom = 1.15
            case .fight:
                audio.play(.horn)
                audio.play(.voFight)
                hud.announce("FIGHT!", color: Theme.goldUI, hold: 0.5, size: 72)
            case let .hit(attacker, impact, at, damage, counter, combo):
                let defender = 1 - attacker
                audio.play(.hit(impact))
                if impact >= .medium, Double.random(in: 0...1) < (impact >= .heavy ? 0.7 : 0.35) {
                    audio.playAny(FighterVoice.of(f(defender).hero.id).hurts, volume: 0.8)
                }
                Effects.hitSpark(at: point(at), impact: impact, color: looks[attacker].energy, in: world)
                fighterNodes[defender].hitFlash(.white, frames: impact >= .heavy ? 4 : 2)
                addShake(impact)
                if attacker == 0 || setup.mode == .versusLocal { Haptics.impact(impact) }
                if counter { Effects.floatingText("COUNTER", at: CGPoint(x: at.x, y: at.y + 60), color: UIColor(hex: 0xFF8A5C), in: world, size: 22) }
                hud.showCombo(attacker: attacker, count: combo, damage: damage)
                if impact >= .heavy { ControllerInput.shared.rumble(0.6) }
            case let .blocked(defender, at, impact):
                audio.play(.block)
                Effects.hitSpark(at: point(at), impact: impact, color: .white, in: world, blocked: true)
                if defender == 0 { Haptics.impact(.light, blocked: true) }
            case let .armorAbsorbed(defender, at):
                audio.play(.armor)
                Effects.hitSpark(at: point(at), impact: .medium, color: looks[defender].energy, in: world, blocked: true)
                fighterNodes[defender].hitFlash(looks[defender].energy, frames: 4)
                Effects.floatingText("ARMOUR", at: CGPoint(x: at.x, y: at.y + 50), color: looks[defender].energy, in: world, size: 18)
            case let .counterTriggered(defender):
                audio.play(.counter)
                fighterNodes[defender].hitFlash(looks[defender].energy, frames: 6)
                let f = match.fighters[defender]
                Effects.floatingText("SHIELD WALL", at: CGPoint(x: f.position.x, y: f.position.y + 200), color: looks[defender].energy, in: world, size: 20)
            case .whiff:
                break          // the swing was heard as it started (see swingSounds)
            case let .special(attacker, name):
                let f = match.fighters[attacker]
                Effects.floatingText(name.uppercased(), at: CGPoint(x: f.position.x, y: f.position.y + 220 * f.stature), color: looks[attacker].energy, in: world, size: 18)
                audio.play(.whooshHeavy, volume: 0.6)
                if f.hero.special == .imperialResolve || f.hero.special == .ironFormation { audio.play(.heal, volume: 0.6) }
                if [.flankingCharge, .royalCharge].contains(f.hero.special) { audio.play(.gallop, volume: 0.8) }
                if f.hero.special == .desertWind { audio.play(.dust) }
            case let .superFlash(attacker, name):
                audio.play(.superFlash)
                showSuperCutIn(attacker: attacker, name: name)
                if f(attacker).hero.archetype == .rider { audio.play(.gallop) }
            case let .projectileLaunched(owner, kind):
                switch kind {
                case .bolt: audio.play(.crossbow)
                case .arrow, .fallingArrow: audio.play(.bow)
                case .orb, .sunbeam: audio.play(.orb)
                case .seal: audio.play(.seal, volume: 0.6)
                case .cavalry: audio.play(.gallop)
                case .dust: break
                case .wave: audio.play(.whooshHeavy)
                }
                _ = owner
            case let .projectileClash(at):
                audio.play(.block)
                Effects.hitSpark(at: point(at), impact: .medium, color: .white, in: world, blocked: true)
            case .thrown:
                audio.play(.grab)
            case let .throwBroken(at):
                audio.play(.block)
                Effects.hitSpark(at: point(at), impact: .medium, color: .white, in: world, blocked: true)
                Effects.floatingText("BREAK", at: CGPoint(x: at.x, y: at.y + 60), color: .white, in: world, size: 20)
            case let .jumped(fighter):
                audio.play(.jump, volume: 0.5)
                Effects.dust(at: CGPoint(x: f(fighter).position.x, y: 0), in: world, amount: 8)
            case let .landed(fighter, hard):
                if hard, audio.has(.bodyFall) { audio.play(.bodyFall) } else { audio.play(.land, volume: hard ? 1 : 0.5) }
                Effects.dust(at: CGPoint(x: f(fighter).position.x, y: 0), in: world, amount: hard ? 22 : 8)
                if hard { addShake(.medium) }
            case let .dashed(fighter, _):
                audio.play(.dash, volume: 0.6)
                Effects.dust(at: CGPoint(x: f(fighter).position.x, y: 0), in: world, amount: 10)
            case let .conditionGained(fighter, condition):
                let p = f(fighter).position
                let text: String = switch condition { case .empowered: "EMPOWERED"; case .fortified: "FORTIFIED"; case .marked: "MARKED"; case .dusted: "SLOWED" }
                Effects.floatingText(text, at: CGPoint(x: p.x, y: p.y + 190), color: condition == .marked || condition == .dusted ? UIColor(hex: 0xFF9C7A) : UIColor(hex: 0x9FE3B8), in: world, size: 16)
            case let .healed(fighter, amount):
                let p = f(fighter).position
                Effects.floatingText("+\(Int(amount))", at: CGPoint(x: p.x, y: p.y + 160), color: UIColor(hex: 0x9FE3B8), in: world, size: 18)
            case let .ko(loser):
                audio.play(.ko)
                audio.play(FighterVoice.of(f(loser).hero.id).knockout, volume: 0.9)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { audio.play(.voKO) }
                slowMotion = 70
                zoom = 1.3
                fighterNodes[loser].hitFlash(.white, frames: 8)
                Haptics.knockout()
                hud.announce("K.O.", color: UIColor(hex: 0xFF5D4A), hold: 1.4, size: 96)
            case .timeOver:
                audio.play(.gong)
                audio.play(.voTime)
                hud.announce("TIME", hold: 1.2)
            case let .roundWon(winner, perfect):
                if let winner {
                    let name = setup.match.bosses.contains(winner) ? "The Echo" : match.fighters[winner].hero.name
                    if perfect {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                            self?.hud.announce("PERFECT", sub: "\(name) takes the round", color: Theme.goldUI)
                            audio.play(.voPerfect)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.hud.announce("\(name.uppercased()) WINS", sub: "the round", hold: 1.0, size: 40) }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.hud.announce("DRAW", hold: 1.0) }
                }
            case let .matchWon(winner):
                audio.play(.victory)
                if winner == 0 || setup.mode == .versusLocal { Haptics.success() }
                let hero = match.fighters[winner].hero
                let line = setup.match.bosses.contains(winner) ? "The mist does not tire." : hero.victory
                let title = setup.match.bosses.contains(winner) ? "THE ECHO PREVAILS" : "\(hero.name.uppercased()) WINS"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.hud.announce(title, sub: "“\(line)”", color: Theme.goldUI, hold: 2.0, size: 42)
                }
            }
        }
    }

    private func f(_ i: Int) -> Fighter { match.fighters[i] }

    private func addShake(_ impact: Impact) {
        guard settings.screenShake, !UIAccessibility.isReduceMotionEnabled else { return }
        let amount: CGFloat = switch impact { case .light: 2; case .medium: 4; case .heavy: 8; case .crushing: 13 }
        shake = max(shake, amount)
    }

    private func showSuperCutIn(attacker: Int, name: String) {
        superCurtain.removeAllActions()
        superCurtain.run(.sequence([.fadeAlpha(to: 0.55, duration: 0.08), .wait(forDuration: 0.5), .fadeAlpha(to: 0, duration: 0.25)]))
        cutIn.removeAllChildren()
        let hero = match.fighters[attacker].hero
        let fromLeft = attacker == 0
        let band = SKShapeNode(rectOf: CGSize(width: size.width * 1.4, height: size.height * 0.42))
        band.fillColor = looks[attacker].energy.withAlphaComponent(0.25)
        band.strokeColor = looks[attacker].energy
        band.lineWidth = 3
        band.zRotation = fromLeft ? 0.08 : -0.08
        cutIn.addChild(band)
        if let image = ArtLibrary.portrait(hero.id) {
            let portrait = SKSpriteNode(texture: SKTexture(image: image))
            let h = size.height * 0.62
            portrait.size = CGSize(width: h * image.size.width / image.size.height, height: h)
            let crop = SKCropNode()
            let mask = SKSpriteNode(color: .white, size: CGSize(width: size.width * 1.4, height: size.height * 0.42))
            mask.zRotation = band.zRotation
            crop.maskNode = mask
            crop.addChild(portrait)
            portrait.position = CGPoint(x: (fromLeft ? -1 : 1) * size.width * 0.22, y: -size.height * 0.04)
            if setup.match.bosses.contains(attacker) { portrait.color = UIColor(hex: 0x8FA6C4); portrait.colorBlendFactor = 0.7 }
            cutIn.addChild(crop)
            portrait.run(.moveBy(x: (fromLeft ? 1 : -1) * 40, y: 0, duration: 0.6))
        }
        let label = SKLabelNode(text: name.uppercased())
        label.fontName = Theme.displayFontName
        label.fontSize = min(44, size.width * 0.05)
        label.fontColor = .white
        label.horizontalAlignmentMode = fromLeft ? .left : .right
        label.position = CGPoint(x: (fromLeft ? -0.02 : 0.02) * size.width, y: -12)
        cutIn.addChild(label)
        let sub = SKLabelNode(text: "CROSSING ART")
        sub.fontName = Theme.bodyFontName
        sub.fontSize = 14
        sub.fontColor = Theme.goldUI
        sub.horizontalAlignmentMode = label.horizontalAlignmentMode
        sub.position = CGPoint(x: label.position.x, y: 30)
        cutIn.addChild(sub)
        cutIn.position = CGPoint(x: (fromLeft ? -1 : 1) * size.width, y: 0)
        cutIn.alpha = 1
        cutIn.removeAllActions()
        cutIn.run(.sequence([.move(to: .zero, duration: 0.12), .wait(forDuration: 0.42), .group([.fadeOut(withDuration: 0.15), .moveBy(x: (fromLeft ? 1 : -1) * 80, y: 0, duration: 0.15)])]))
    }

    // MARK: Drawing

    private func renderFrame() {
        for i in 0..<2 { fighterNodes[i].update(match.fighters[i], clock: match.frameCount) }
        // Whoever attacked last draws in front, and stays there until the other one attacks (switching back the
        // moment an attack ends flickers the overlapping figures).
        for i in 0..<2 where match.fighters[i].action.isAttack && !match.fighters[1 - i].action.isAttack { frontFighter = i }
        fighterNodes[frontFighter].zPosition = 12
        fighterNodes[1 - frontFighter].zPosition = 11

        var alive = Set<Int>()
        for p in match.projectiles {
            alive.insert(p.id)
            let node: ProjectileNode
            if let existing = projectileNodes[p.id] { node = existing } else {
                node = ProjectileNode(p, color: looks[p.owner].energy)
                world.addChild(node)
                projectileNodes[p.id] = node
            }
            node.update(p)
        }
        for (id, node) in projectileNodes where !alive.contains(id) {
            node.run(.sequence([.fadeOut(withDuration: 0.1), .removeFromParent()]))
            projectileNodes[id] = nil
        }

        hud.update(match)
        if match.frameCount % 20 == 0, let view {
            let a = Int((match.healthFraction(0) * 100).rounded()), b = Int((match.healthFraction(1) * 100).rounded())
            view.accessibilityValue = "\(match.fighters[0].hero.name) \(a) percent, \(match.fighters[1].hero.name) \(b) percent, \(match.secondsLeft) seconds"
        }
        controls?.setSuperReady(match.fighters[0].meter >= 100)
        updateCamera()
        if showHitboxes { drawHitboxes() }
    }

    private func updateCamera() {
        let a = match.fighters[0].position, b = match.fighters[1].position
        let separation = CGFloat(abs(a.x - b.x))
        let midX = CGFloat(a.x + b.x) / 2
        // Fit both fighters with room to spare; show at least ~430 units of height.
        // Wider screens see more of the stage; taller ones (iPad) more sky.
        let visibleWidth = max(size.width / size.height > 1.6 ? 640 : 780, separation + 300)
        var scale = min(size.width / visibleWidth, size.height / 430)
        scale *= zoom
        zoom += (1 - zoom) * 0.04
        let halfVisible = size.width / scale / 2
        let limit = Match.stageHalfWidth + 90 - halfVisible
        let targetX = limit > 0 ? max(-limit, min(limit, midX)) : 0
        cameraX += (targetX - cameraX) * 0.18
        let highest = CGFloat(max(a.y, b.y))
        let groundScreenY = -size.height / 2 + size.height * 0.16
        let lift = max(0, highest - 200) * 0.35
        var offset = CGPoint.zero
        if shake > 0.3 {
            offset = CGPoint(x: CGFloat.random(in: -shake...shake), y: CGFloat.random(in: -shake...shake) * 0.6)
            shake *= 0.82
        } else { shake = 0 }
        world.setScale(scale)
        world.position = CGPoint(x: -cameraX * scale + offset.x, y: groundScreenY - lift * scale + offset.y)
        stage.parallax(cameraX: cameraX)
    }

    private func drawHitboxes() {
        hitboxLayer.removeAllChildren()
        func box(_ b: Box, _ color: UIColor) {
            let node = SKShapeNode(rect: CGRect(x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY))
            node.strokeColor = color
            node.fillColor = color.withAlphaComponent(0.15)
            node.lineWidth = 1.5
            hitboxLayer.addChild(node)
        }
        for f in match.fighters {
            for h in f.hurtboxes { box(h, UIColor(hex: 0x4FD06A)) }
            if let move = f.currentMove, move.hitbox.width > 0, f.frame >= move.firstActive, f.frame <= move.lastActive {
                box(Box(local: move.hitbox, origin: f.position, facing: f.facing), UIColor(hex: 0xFF4A4A))
            }
        }
        for p in match.projectiles where p.armed { box(p.box, UIColor(hex: 0xFFB04A)) }
    }

    /// Frame data readout for training mode.
    var trainingReadout: String {
        let f = match.fighters[0]
        guard let move = f.currentMove else { return "" }
        return "\(move.name): \(move.startup)f startup · \(move.active)f active · \(move.recovery)f recovery"
    }
}
