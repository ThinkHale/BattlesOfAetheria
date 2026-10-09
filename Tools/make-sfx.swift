// Synthesizes the combat sound effects into App/Resources/Audio as small WAV
// files: run `swift Tools/make-sfx.swift` from the repo root. The palette
// follows Aetheria Rising's audio brief: wood, bronze, skin drums, bowstrings
// and horn, nothing electronic. A recorded file dropped in with the same name
// replaces a synthesized one: list its name (e.g. sfx-hit-light) in
// Tools/recorded-sounds.txt and this script leaves it alone. Afterwards run
// Tools/level-sfx.py, which sets each sound's loudness for phone speakers.
import Foundation

let rate = 44_100.0
var seed: UInt64 = 0x5EED

func noise() -> Double {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return Double(seed % 2_000_001) / 1_000_000 - 1
}

struct Sound {
    var samples: [Double]
    init(seconds: Double) { samples = Array(repeating: 0, count: Int(seconds * rate)) }

    /// Adds a voice: `wave(t, phase)` shaped by `envelope(t)`.
    mutating func add(from start: Double = 0, seconds: Double, gain: Double = 1,
                      envelope: (Double) -> Double, wave: (Double) -> Double) {
        let first = Int(start * rate)
        for i in 0..<Int(seconds * rate) where first + i < samples.count {
            let t = Double(i) / rate
            samples[first + i] += wave(t) * envelope(t) * gain
        }
    }

    /// A one-pole low-pass, for taking the edge off noise.
    mutating func lowpass(_ amount: Double) {
        var last = 0.0
        for i in samples.indices { last += (samples[i] - last) * amount; samples[i] = last }
    }

    /// A short room: a few decaying echoes.
    mutating func room(_ wet: Double = 0.25) {
        let taps: [(Double, Double)] = [(0.031, 0.5), (0.047, 0.38), (0.071, 0.27), (0.113, 0.18), (0.167, 0.11)]
        let dry = samples
        for (delay, gain) in taps {
            let offset = Int(delay * rate)
            for i in offset..<samples.count { samples[i] += dry[i - offset] * gain * wet }
        }
    }

    func write(_ name: String) throws {
        let peak = max(0.0001, samples.map(abs).max() ?? 1)
        let scale = 0.89 / peak
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s * scale)) * 32_767))) }
        try data.write(to: URL(fileURLWithPath: "App/Resources/Audio/\(name).wav"))
    }
}

let tau = 2 * Double.pi
func decay(_ rate: Double) -> (Double) -> Double { { t in exp(-t * rate) } }
func attackDecay(_ attack: Double, _ rate: Double) -> (Double) -> Double { { t in min(1, t / attack) * exp(-max(0, t - attack) * rate) } }

/// A skin-drum thump: a sine that drops in pitch.
func drum(_ s: inout Sound, at: Double = 0, from f0: Double, to f1: Double, seconds: Double, gain: Double = 1) {
    var phase = 0.0
    s.add(from: at, seconds: seconds, gain: gain, envelope: decay(6 / seconds)) { t in
        let f = f1 + (f0 - f1) * exp(-t * 28)
        phase += tau * f / rate
        return sin(phase)
    }
}

/// A struck bronze: inharmonic partials ringing out.
func bronze(_ s: inout Sound, at: Double = 0, base: Double, seconds: Double, gain: Double = 1) {
    for (ratio, amp, rate) in [(1.0, 1.0, 5.0), (2.76, 0.6, 8.0), (5.40, 0.4, 12.0), (8.93, 0.25, 18.0), (13.3, 0.12, 26.0)] {
        s.add(from: at, seconds: seconds, gain: gain * amp, envelope: decay(rate / seconds * 0.6)) { t in sin(tau * base * ratio * t) }
    }
}

func burst(_ s: inout Sound, at: Double = 0, seconds: Double, gain: Double, rate: Double) {
    s.add(from: at, seconds: seconds, gain: gain, envelope: decay(rate)) { _ in noise() }
}

var sounds: [String: Sound] = [:]

// Blows landing: cloth and leather slap over a drum body, heavier as they go.
for (name, body, low, length, slap) in [("hit-light", 190.0, 110.0, 0.16, 0.7), ("hit-medium", 150.0, 80.0, 0.24, 0.8),
                                        ("hit-heavy", 120.0, 55.0, 0.36, 0.9), ("hit-crushing", 100.0, 42.0, 0.6, 1.0)] {
    var s = Sound(seconds: length + 0.2)
    burst(&s, seconds: 0.05, gain: slap, rate: 70)
    s.lowpass(0.45)
    drum(&s, from: body, to: low, seconds: length, gain: 1.1)
    if name == "hit-crushing" { drum(&s, at: 0.02, from: 70, to: 34, seconds: 0.7, gain: 0.8) }
    s.room(0.2)
    sounds[name] = s
}

// A guard: bronze shield struck, a short bright ring.
do {
    var s = Sound(seconds: 0.45)
    burst(&s, seconds: 0.02, gain: 0.5, rate: 120)
    bronze(&s, base: 420, seconds: 0.4, gain: 0.7)
    s.room(0.15)
    sounds["block"] = s

    var armor = Sound(seconds: 0.5)
    bronze(&armor, base: 190, seconds: 0.45, gain: 0.8)
    drum(&armor, from: 130, to: 70, seconds: 0.25, gain: 0.7)
    armor.room(0.2)
    sounds["armor"] = armor

    var counter = Sound(seconds: 0.8)
    bronze(&counter, base: 620, seconds: 0.7, gain: 0.8)
    bronze(&counter, at: 0.05, base: 930, seconds: 0.6, gain: 0.4)
    counter.room(0.3)
    sounds["counter"] = counter
}

// Swings through air.
for (name, seconds, sweep) in [("whoosh-light", 0.16, 0.25), ("whoosh-heavy", 0.3, 0.12)] {
    var s = Sound(seconds: seconds + 0.05)
    s.add(seconds: seconds, gain: 0.8, envelope: { t in sin(Double.pi * min(1, t / seconds)) }) { _ in noise() }
    s.lowpass(sweep)
    sounds[name] = s
}

// A bowstring and a crossbow.
do {
    var bow = Sound(seconds: 0.4)
    var phase = 0.0
    bow.add(seconds: 0.35, gain: 0.9, envelope: decay(14)) { t in
        phase += tau * (180 - 60 * t) / rate
        return sin(phase) + 0.4 * sin(phase * 2.01) + 0.2 * sin(phase * 3.03)
    }
    burst(&bow, seconds: 0.03, gain: 0.3, rate: 90)
    sounds["bow"] = bow

    var crossbow = Sound(seconds: 0.3)
    burst(&crossbow, seconds: 0.015, gain: 0.9, rate: 200)
    bronze(&crossbow, base: 900, seconds: 0.08, gain: 0.3)
    drum(&crossbow, at: 0.005, from: 260, to: 150, seconds: 0.12, gain: 0.7)
    sounds["crossbow"] = crossbow
}

// Sunlight, seals and dust.
do {
    var orb = Sound(seconds: 0.9)
    for (i, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
        orb.add(from: Double(i) * 0.05, seconds: 0.8, gain: 0.35, envelope: attackDecay(0.04, 4)) { t in sin(tau * f * t) * (1 + 0.3 * sin(tau * 6 * t)) }
    }
    orb.room(0.35)
    sounds["orb"] = orb

    var seal = Sound(seconds: 0.7)
    bronze(&seal, base: 300, seconds: 0.5, gain: 0.5)
    drum(&seal, at: 0.0, from: 160, to: 60, seconds: 0.5, gain: 1)
    burst(&seal, seconds: 0.2, gain: 0.5, rate: 15)
    seal.lowpass(0.5)
    seal.room(0.3)
    sounds["seal"] = seal

    var dust = Sound(seconds: 0.7)
    dust.add(seconds: 0.65, gain: 0.6, envelope: { t in min(1, t / 0.08) * exp(-t * 4) }) { _ in noise() }
    dust.lowpass(0.12)
    sounds["dust"] = dust

    var gallop = Sound(seconds: 1.0)
    for i in 0..<8 {
        let at = Double(i) * 0.115 + (i % 2 == 0 ? 0 : 0.03)
        drum(&gallop, at: at, from: 210, to: 120, seconds: 0.09, gain: 0.8 - Double(i) * 0.05)
        burst(&gallop, at: at, seconds: 0.03, gain: 0.25, rate: 80)
    }
    gallop.lowpass(0.5)
    sounds["gallop"] = gallop
}

// Movement.
do {
    var jump = Sound(seconds: 0.2)
    jump.add(seconds: 0.18, gain: 0.5, envelope: { t in sin(Double.pi * min(1, t / 0.18)) }) { _ in noise() }
    jump.lowpass(0.18)
    sounds["jump"] = jump

    var land = Sound(seconds: 0.25)
    drum(&land, from: 120, to: 60, seconds: 0.18, gain: 0.6)
    burst(&land, seconds: 0.06, gain: 0.3, rate: 50)
    land.lowpass(0.3)
    sounds["land"] = land

    var dash = Sound(seconds: 0.25)
    dash.add(seconds: 0.22, gain: 0.6, envelope: decay(10)) { _ in noise() }
    dash.lowpass(0.2)
    sounds["dash"] = dash

    var grab = Sound(seconds: 0.3)
    burst(&grab, seconds: 0.04, gain: 0.8, rate: 60)
    grab.lowpass(0.35)
    drum(&grab, at: 0.01, from: 140, to: 90, seconds: 0.2, gain: 0.7)
    sounds["grab"] = grab
}

// Announcements: a gong for the round, a horn for the fight, a great drum for a KO.
do {
    var gong = Sound(seconds: 3.2)
    bronze(&gong, base: 98, seconds: 3.0, gain: 1)
    bronze(&gong, base: 147, seconds: 2.4, gain: 0.4)
    drum(&gong, from: 90, to: 60, seconds: 0.6, gain: 0.6)
    gong.room(0.3)
    sounds["gong"] = gong

    var horn = Sound(seconds: 1.5)
    for (f, amp) in [(146.83, 1.0), (220.0, 0.6)] {
        var phase = 0.0
        horn.add(seconds: 1.3, gain: amp, envelope: { t in min(1, t / 0.12) * (t < 0.9 ? 1 : exp(-(t - 0.9) * 8)) }) { t in
            phase += tau * f * (1 + 0.004 * sin(tau * 5 * t)) / rate
            var v = 0.0
            for k in 1...8 { v += sin(phase * Double(k)) / Double(k) * (k % 2 == 1 ? 1 : 0.6) }
            return v
        }
    }
    horn.lowpass(0.16)
    horn.room(0.35)
    sounds["horn"] = horn

    var ko = Sound(seconds: 2.4)
    drum(&ko, from: 90, to: 36, seconds: 1.8, gain: 1.2)
    drum(&ko, at: 0.35, from: 80, to: 34, seconds: 1.5, gain: 0.9)
    bronze(&ko, base: 73, seconds: 2.2, gain: 0.5)
    ko.room(0.4)
    sounds["ko"] = ko

    var flash = Sound(seconds: 1.2)
    for i in 0..<10 { drum(&flash, at: Double(i) * 0.07, from: 160 + Double(i) * 12, to: 100, seconds: 0.12, gain: 0.3 + Double(i) * 0.06) }
    for (f, amp) in [(293.66, 0.5), (440.0, 0.4), (587.33, 0.3)] {
        flash.add(seconds: 1.1, gain: amp, envelope: { t in min(1, t / 0.6) * exp(-max(0, t - 0.7) * 6) }) { t in sin(tau * f * t) + 0.3 * sin(tau * f * 2 * t) }
    }
    flash.room(0.4)
    sounds["super"] = flash

    var heal = Sound(seconds: 1.4)
    for (i, f) in [392.0, 493.88, 587.33, 739.99, 783.99].enumerated() {
        var phase = 0.0
        heal.add(from: Double(i) * 0.09, seconds: 1.0, gain: 0.45, envelope: decay(4)) { _ in
            phase += tau * f / rate
            return sin(phase) + 0.5 * sin(phase * 2) + 0.2 * sin(phase * 3)
        }
    }
    heal.room(0.4)
    sounds["heal"] = heal

    var victory = Sound(seconds: 2.4)
    for (i, f) in [261.63, 329.63, 392.0, 523.25, 392.0, 523.25].enumerated() {
        var phase = 0.0
        victory.add(from: Double(i) * 0.13, seconds: 1.4, gain: 0.5, envelope: decay(3.5)) { _ in
            phase += tau * f / rate
            return sin(phase) + 0.45 * sin(phase * 2) + 0.25 * sin(phase * 3) + 0.1 * sin(phase * 4)
        }
    }
    victory.room(0.45)
    sounds["victory"] = victory
}

// Recorded replacements are never overwritten.
let recorded = Set(((try? String(contentsOfFile: "Tools/recorded-sounds.txt", encoding: .utf8)) ?? "")
    .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") })
var written = 0
for (name, sound) in sounds.sorted(by: { $0.key < $1.key }) where !recorded.contains("sfx-\(name)") {
    try sound.write("sfx-\(name)")
    written += 1
}
print("Wrote \(written) sounds to App/Resources/Audio (\(sounds.count - written) recorded ones left alone)")
