import Foundation
import FightCore

/// Everything the game remembers between launches, saved as JSON in
/// UserDefaults. Small, local, and never sent anywhere.
struct Profile: Codable, Equatable {
    struct Settings: Codable, Equatable {
        var musicVolume = 0.7
        var effectsVolume = 0.9
        var haptics = true
        var screenShake = true
        var difficulty: Difficulty = .soldier
        var roundsToWin = 2
        var roundSeconds = 99
        var showInputHints = true
        /// Puts the attack buttons on the left and the stick on the right.
        var swapControls = false
        var controlsScale = 1.0
        var controlsOpacity = 0.85
    }

    struct HeroRecord: Codable, Equatable {
        var wins = 0
        var losses = 0
        var arcadeClears = 0
        var bestArcadeScore = 0
        /// Cleared arcade on Champion or higher; unlocks the alternate palette.
        var clearedOnChampion = false
    }

    var settings = Settings()
    var heroes: [String: HeroRecord] = [:]
    var highScore = 0
    var totalKOs = 0
    var matchesPlayed = 0
    var seenHowToPlay = false
    var lastHero: HeroID? = nil
    var arcadeInProgress: ArcadeRun? = nil

    func record(_ hero: HeroID) -> HeroRecord { heroes[hero.rawValue] ?? HeroRecord() }

    mutating func update(_ hero: HeroID, _ change: (inout HeroRecord) -> Void) {
        var record = record(hero)
        change(&record)
        heroes[hero.rawValue] = record
    }

    /// The palette unlocked for a hero by clearing arcade with them.
    func hasAltPalette(_ hero: HeroID) -> Bool { record(hero).arcadeClears > 0 }
}

// Saves from older versions (or newer ones, after a downgrade) must still load: every field falls back to its default
// when it is missing or unreadable, instead of the whole profile failing to decode and being replaced by a blank one
// on the next save.
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T { (try? decodeIfPresent(T.self, forKey: key)) ?? fallback }
}

extension Profile.Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = Self()
        self.init(musicVolume: c.value(.musicVolume, d.musicVolume), effectsVolume: c.value(.effectsVolume, d.effectsVolume),
                  haptics: c.value(.haptics, d.haptics), screenShake: c.value(.screenShake, d.screenShake),
                  difficulty: c.value(.difficulty, d.difficulty), roundsToWin: c.value(.roundsToWin, d.roundsToWin),
                  roundSeconds: c.value(.roundSeconds, d.roundSeconds), showInputHints: c.value(.showInputHints, d.showInputHints),
                  swapControls: c.value(.swapControls, d.swapControls), controlsScale: c.value(.controlsScale, d.controlsScale),
                  controlsOpacity: c.value(.controlsOpacity, d.controlsOpacity))
    }
}

extension Profile.HeroRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(wins: c.value(.wins, 0), losses: c.value(.losses, 0), arcadeClears: c.value(.arcadeClears, 0),
                  bestArcadeScore: c.value(.bestArcadeScore, 0), clearedOnChampion: c.value(.clearedOnChampion, false))
    }
}

extension Profile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(settings: c.value(.settings, Settings()), heroes: c.value(.heroes, [:]), highScore: c.value(.highScore, 0),
                  totalKOs: c.value(.totalKOs, 0), matchesPlayed: c.value(.matchesPlayed, 0),
                  seenHowToPlay: c.value(.seenHowToPlay, false), lastHero: c.value(.lastHero, nil),
                  arcadeInProgress: c.value(.arcadeInProgress, nil))   // an unreadable run is dropped, not the profile
    }
}

/// An arcade run in progress, so quitting mid-ladder can be resumed.
struct ArcadeRun: Codable, Equatable {
    var player: HeroID
    var difficulty: Difficulty
    var seed: UInt64
    var rung: Int
    var score: Int
    var continuesUsed: Int
    var altPalette: Bool

    var ladder: ArcadeLadder { ArcadeLadder(player: player, base: difficulty, seed: seed) }
}

@MainActor
final class ProfileStore: ObservableObject {
    static let key = "aetheria.clash.profile.v1"

    @Published var profile: Profile {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-resetProfile") {
            defaults.removeObject(forKey: Self.key)
        }
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = saved
        } else {
            profile = Profile()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
