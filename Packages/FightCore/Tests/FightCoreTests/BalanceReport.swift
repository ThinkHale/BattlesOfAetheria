import XCTest
@testable import FightCore

/// A fuller balance picture than BalanceTests, for tuning by hand:
///   BALANCE=1 swift test --filter BalanceReport
/// Prints win rates per difficulty, the matchup matrix at Champion, and how each commander wins
/// (damage per round, round length, time-outs, specials and supers used).
final class BalanceReport: XCTestCase {
    struct Line { var wins = 0, games = 0, rounds = 0, timeOuts = 0, ticks = 0; var damage = 0.0, specials = 0, supers = 0, throwsLanded = 0, hits = 0 }

    static func play(_ a: HeroID, _ b: HeroID, seed: Int, difficulty: Difficulty) -> (winner: Int?, match: Match, ticks: Int, rounds: Int, timeOuts: Int) {
        var match = Match(config: MatchConfig(heroes: [a, b], stage: .crossing, roundsToWin: 2, seed: UInt64(seed * 31 + 7)))
        var cpuA = CPU(difficulty: difficulty, seed: UInt64(seed * 2 + 1)), cpuB = CPU(difficulty: difficulty, seed: UInt64(seed * 2 + 2))
        var ticks = 0, rounds = 0, timeOuts = 0
        while !match.isOver && ticks < 60 * 60 * 10 {
            match.tick([cpuA.controls(for: 0, in: match), cpuB.controls(for: 1, in: match)])
            ticks += 1
            for e in match.events {
                if case .roundWon = e { rounds += 1 }
                if case .timeOver = e { timeOuts += 1 }
            }
        }
        if case let .matchOver(w) = match.phase { return (w, match, ticks, rounds, timeOuts) }
        return (nil, match, ticks, rounds, timeOuts)
    }

    func testReport() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BALANCE"] != nil)
        let seeds = Int(ProcessInfo.processInfo.environment["SEEDS"] ?? "") ?? 4
        let heroes = HeroID.allCases
        for difficulty in [Difficulty.soldier, .champion, .legend] {
            var lines: [HeroID: Line] = [:]
            var matrix: [HeroID: [HeroID: Int]] = [:]
            for a in heroes {
                for b in heroes where a != b {
                    for seed in 0..<seeds {
                        let r = Self.play(a, b, seed: seed, difficulty: difficulty)
                        for (i, h) in [a, b].enumerated() {
                            var l = lines[h, default: Line()]
                            l.games += 1; l.rounds += r.rounds; l.timeOuts += r.timeOuts; l.ticks += r.ticks
                            let st = r.match.fighters[i].stats
                            l.damage += st.damageDealt; l.specials += st.specialsUsed; l.supers += st.supersUsed
                            l.throwsLanded += st.throwsLanded; l.hits += st.hitsLanded
                            if r.winner == i { l.wins += 1; matrix[h, default: [:]][i == 0 ? b : a, default: 0] += 1 }
                            lines[h] = l
                        }
                    }
                }
            }
            print("== \(difficulty.name): \(seeds) seeds per ordered pairing")
            print("REPORT hero          win   dmg/rnd  rnd(s)  timeouts  spec/m  super/m  throws/m  hits/m")
            for (h, l) in lines.sorted(by: { Double($0.value.wins) / Double($0.value.games) > Double($1.value.wins) / Double($1.value.games) }) {
                let g = Double(l.games), rds = Double(max(1, l.rounds))
                print(String(format: "REPORT %-13@ %5.2f %8.0f %7.1f %9.2f %7.1f %8.2f %9.2f %7.1f",
                             h.rawValue as NSString, Double(l.wins) / g, l.damage / rds, Double(l.ticks) / 60 / rds,
                             Double(l.timeOuts) / g, Double(l.specials) / g, Double(l.supers) / g, Double(l.throwsLanded) / g, Double(l.hits) / g))
            }
            if difficulty == .champion {
                print("MATRIX row beats column, wins out of \(2 * seeds)")
                print("MATRIX " + "".padding(toLength: 12, withPad: " ", startingAt: 0) + heroes.map { String($0.rawValue.prefix(5)).padding(toLength: 6, withPad: " ", startingAt: 0) }.joined())
                for a in heroes {
                    let row = heroes.map { b in a == b ? "  -   " : String(matrix[a]?[b] ?? 0).padding(toLength: 6, withPad: " ", startingAt: 0) }.joined()
                    print("MATRIX " + a.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0) + row)
                }
            }
        }
    }
}
