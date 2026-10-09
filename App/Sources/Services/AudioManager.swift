import AVFoundation
import FightCore

enum SoundEffect: String, CaseIterable {
    case hitLight = "sfx-hit-light", hitMedium = "sfx-hit-medium", hitHeavy = "sfx-hit-heavy", hitCrushing = "sfx-hit-crushing"
    case block = "sfx-block", armor = "sfx-armor", counter = "sfx-counter"
    case whooshLight = "sfx-whoosh-light", whooshHeavy = "sfx-whoosh-heavy"
    case bow = "sfx-bow", crossbow = "sfx-crossbow", orb = "sfx-orb", seal = "sfx-seal", dust = "sfx-dust", gallop = "sfx-gallop"
    case jump = "sfx-jump", land = "sfx-land", dash = "sfx-dash", grab = "sfx-grab"
    case gong = "sfx-gong", horn = "sfx-horn", ko = "sfx-ko", superFlash = "sfx-super", heal = "sfx-heal", victory = "sfx-victory"
    case tap = "ui-tap", select = "ui-empire-chosen", reward = "ui-reward", error = "ui-error"
    // Recorded only (no synthesized stand-in): silent until the file is bundled.
    case swingThrust = "sfx-swing-thrust", bodyFall = "sfx-bodyfall"
    case voRound1 = "vo-round-1", voRound2 = "vo-round-2", voRound3 = "vo-round-3", voFinalRound = "vo-final-round"
    case voFight = "vo-fight", voKO = "vo-ko", voTime = "vo-time", voPerfect = "vo-perfect"
    case maleAttack1 = "vo-male-attack-1", maleAttack2 = "vo-male-attack-2", maleAttack3 = "vo-male-attack-3"
    case maleHurt1 = "vo-male-hurt-1", maleHurt2 = "vo-male-hurt-2", maleHurt3 = "vo-male-hurt-3", maleKO = "vo-male-ko"
    case femaleAttack1 = "vo-female-attack-1", femaleAttack2 = "vo-female-attack-2", femaleAttack3 = "vo-female-attack-3"
    case femaleHurt1 = "vo-female-hurt-1", femaleHurt2 = "vo-female-hurt-2", femaleHurt3 = "vo-female-hurt-3", femaleKO = "vo-female-ko"

    /// Long sounds get their own voices so a flurry of blows can't cut them off.
    var isLong: Bool { [.gong, .horn, .ko, .victory, .superFlash, .gallop].contains(self) }
    /// The announcer speaks on one voice of its own: a new line replaces the last, never talks over it.
    var isAnnouncer: Bool { rawValue.hasPrefix("vo-") && !rawValue.contains("male") }

    static func announce(round: Int, final: Bool) -> SoundEffect {
        final ? .voFinalRound : [.voRound1, .voRound2, .voRound3][min(2, max(0, round - 1))]
    }

    static func hit(_ impact: Impact) -> SoundEffect {
        switch impact {
        case .light: .hitLight
        case .medium: .hitMedium
        case .heavy: .hitHeavy
        case .crushing: .hitCrushing
        }
    }
}

enum MusicTrack: String {
    case title = "music-title"
    case select = "music-march"
    case rome = "music-kingdom-rome", egypt = "music-kingdom-egypt", persia = "music-kingdom-persia", han = "music-kingdom-han"

    /// Evens out the tracks' loudness (measured RMS: egypt -19.4, march -17.0, rome -13.5, title -11.5, han -11.2,
    /// persia -11.0 dBFS) toward -17; the two quiet ones can't be raised past full volume.
    var gain: Float {
        switch self {
        case .egypt, .select: 1.0
        case .rome: 0.67
        case .title: 0.53
        case .han: 0.52
        case .persia: 0.5
        }
    }

    static func stage(_ stage: StageID) -> MusicTrack {
        switch stage.empire {
        case .rome: .rome
        case .egypt: .egypt
        case .persia: .persia
        case .han: .han
        case nil: .select
        }
    }
}

/// A commander's voice for grunts and cries.
enum FighterVoice {
    case male, female

    static func of(_ hero: HeroID) -> FighterVoice {
        switch hero {
        case .tahmina, .meritamun, .livia, .nefru, .atossa, .meiLin: .female
        default: .male
        }
    }

    var attacks: [SoundEffect] { self == .male ? [.maleAttack1, .maleAttack2, .maleAttack3] : [.femaleAttack1, .femaleAttack2, .femaleAttack3] }
    var hurts: [SoundEffect] { self == .male ? [.maleHurt1, .maleHurt2, .maleHurt3] : [.femaleHurt1, .femaleHurt2, .femaleHurt3] }
    var knockout: SoundEffect { self == .male ? .maleKO : .femaleKO }
}

/// Music and sound effects. Effects are decoded once into memory and played
/// on a small pool of voices so a flurry of blows never stutters (long sounds
/// and the announcer have voices of their own); music crossfades between
/// tracks. Plays alongside other apps' audio and respects the silent switch.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var longVoices: [AVAudioPlayerNode] = []
    private var nextLongVoice = 0
    private let announcerVoice = AVAudioPlayerNode()
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SoundEffect: TimeInterval] = [:]
    private var music: AVAudioPlayer?
    private var fadingOut: AVAudioPlayer?
    private var loopTimer: Timer?
    private var ducked = false
    /// Every track ends in a composed fade; a plain loop would dip to near silence and restart. Instead a fresh copy
    /// crossfades in this many seconds before the end.
    private let loopCrossfade: TimeInterval = 4
    private(set) var currentTrack: MusicTrack?
    private var started = false
    private let sessionQueue = DispatchQueue(label: "aetheria.audio.session", qos: .userInitiated)

    var musicVolume: Float = 0.7 { didSet { music?.volume = targetMusicVolume } }

    private var targetMusicVolume: Float { musicVolume * (ducked ? 0.25 : 0.75) * (currentTrack?.gain ?? 1) }
    var effectsVolume: Float = 0.9 { didSet { engine.mainMixerNode.outputVolume = effectsVolume } }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        // The category is set before the engine starts (it is quick), so the engine never starts under the default
        // category, which would stop the player's own music. Activation can block, so it runs off the main thread
        // and the engine starts once it is done.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        for i in 0..<16 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            if i < 12 { voices.append(voice) } else { longVoices.append(voice) }
        }
        engine.attach(announcerVoice)
        engine.connect(announcerVoice, to: engine.mainMixerNode, format: format)
        for effect in SoundEffect.allCases { buffers[effect] = load(effect.rawValue, format: format) }
        engine.mainMixerNode.outputVolume = effectsVolume
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.async { [weak self] in self?.startEngine() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in self?.resume() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.startEngine() }
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
        for voice in voices + longVoices + [announcerVoice] where !voice.isPlaying { voice.play() }
    }

    func resume() {
        sessionQueue.async { [weak self] in
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.async { [weak self] in
                self?.startEngine()
                self?.music?.play()
            }
        }
    }

    /// Reads a bundled sound (WAV or AAC) into a buffer in the engine's format.
    private func load(_ name: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let url = ["wav", "m4a", "caf"].lazy.compactMap { Bundle.main.url(forResource: name, withExtension: $0) }.first
        guard let url, let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil else { return nil }
        if source.format == format { return source }
        guard let converter = AVAudioConverter(from: source.format, to: format) else { return nil }
        let ratio = format.sampleRate / source.format.sampleRate
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? output : nil
    }

    /// Whether a sound is bundled (the recorded-only ones may not be).
    func has(_ effect: SoundEffect) -> Bool { buffers[effect] != nil }

    /// Plays one of several takes at random (grunts), if any is bundled.
    func playAny(_ effects: [SoundEffect], volume: Float = 1) {
        if let pick = effects.filter({ buffers[$0] != nil }).randomElement() { play(pick, volume: volume) }
    }

    /// Plays an effect. The same effect is not stacked within 30 ms, and a
    /// small pitch-free variation in volume keeps repeats from sounding canned.
    func play(_ effect: SoundEffect, volume: Float = 1) {
        guard started, let buffer = buffers[effect], effectsVolume > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[effect], now - last < 0.03 { return }
        lastPlayed[effect] = now
        if !engine.isRunning { startEngine() }
        let voice: AVAudioPlayerNode
        if effect.isAnnouncer {
            voice = announcerVoice
        } else if effect.isLong {
            voice = longVoices[nextLongVoice]; nextLongVoice = (nextLongVoice + 1) % longVoices.count
        } else {
            voice = voices[nextVoice]; nextVoice = (nextVoice + 1) % voices.count
        }
        voice.volume = volume * Float.random(in: 0.88...1)
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
    }

    func playMusic(_ track: MusicTrack?) {
        guard track != currentTrack else { return }
        currentTrack = track
        fadingOut?.stop()
        if let old = music {
            old.setVolume(0, fadeDuration: 0.8)
            fadingOut = old
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak old] in old?.stop() }
        }
        music = nil
        loopTimer?.invalidate(); loopTimer = nil
        guard let track, let player = makePlayer(track) else { return }
        player.play()
        player.setVolume(targetMusicVolume, fadeDuration: 1.0)
        music = player
        loopTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.continueLoop() }
        }
    }

    private func makePlayer(_ track: MusicTrack) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = 0
        player.volume = 0
        player.prepareToPlay()
        return player
    }

    /// Near the end of the track, crossfade into a fresh copy from the top.
    private func continueLoop() {
        guard let current = music, let track = currentTrack, current.isPlaying,
              current.duration > loopCrossfade * 3, current.currentTime >= current.duration - loopCrossfade,
              let next = makePlayer(track) else { return }
        next.play()
        next.setVolume(targetMusicVolume, fadeDuration: loopCrossfade)
        current.setVolume(0, fadeDuration: loopCrossfade)
        fadingOut?.stop()
        fadingOut = current
        music = next
    }

    func duckMusic(_ ducked: Bool) {
        self.ducked = ducked
        music?.setVolume(targetMusicVolume, fadeDuration: 0.3)
    }
}
