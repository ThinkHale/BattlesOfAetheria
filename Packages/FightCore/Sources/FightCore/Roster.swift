// The commanders of Aetheria Rising, as fighters. Names, titles, empires,
// classes and signature skills follow the strategy game's hero catalog
// (aetheria.rising/functions/heroCatalog.js) and quotes its lore
// (heroLore.js); the fighting lines are written in the voice that lore gives
// each of them.

public enum Empire: String, CaseIterable, Codable, Sendable {
    case rome, egypt, persia, han

    public var displayName: String {
        switch self {
        case .rome: "Rome"
        case .egypt: "Egypt"
        case .persia: "Persia"
        case .han: "Han"
        }
    }
}

/// The three troop classes of the strategy game, which here set how a
/// commander fights: guardians hold ground, riders close distance, archers
/// keep it.
public enum Archetype: String, CaseIterable, Codable, Sendable {
    case guardian, rider, archer

    public var displayName: String {
        switch self {
        case .guardian: "Guardian"
        case .rider: "Rider"
        case .archer: "Archer"
        }
    }
}

public enum HeroID: String, CaseIterable, Codable, Sendable, Identifiable {
    case gaius, zhaoLin = "zhao_lin", tahmina, marcusVarro = "marcus_varro", khepri, bardiya
    case weiJian = "wei_jian", meritamun, arsames, livia, nefru, atossa, meiLin = "mei_lin"

    public var id: String { rawValue }
    public var hero: Hero { Roster.hero(self) }
}

/// What a commander's signature skill does when it is their Special.
public enum SpecialKind: String, Codable, Sendable {
    /// A guarding stance; a blow that lands on it is answered at once.
    case counter
    /// Bolts loosed straight ahead.
    case volley
    /// A hop back with an arrow loosed while airborne.
    case partingShot
    /// A charge through the enemy that ends behind them.
    case flankingCharge
    /// A dash that leaves a cloud of dust which slows whoever stands in it.
    case desertWind
    /// A slow advance that shrugs off blows, ending in a spear thrust.
    case armoredAdvance
    /// A stance that hardens the fighter for a time and rallies their strength.
    case ironFormation
    /// A slow orb that marks the enemy to take more damage.
    case eyeOfHorus
    /// A cavalryman called in from behind who rides the enemy down.
    case levy
    /// A brief rite that steadies the fighter, restoring health and strength.
    case imperialResolve
    /// Arrows loosed high that fall on the enemy's position.
    case sunlitVolley
    /// An armoured mounted charge that launches.
    case royalCharge
    /// A seal set on the ground ahead that bursts a moment later.
    case stratagem
}

public struct HeroStats: Equatable, Codable, Sendable {
    public var health: Double
    public var walkSpeed: Double
    public var dashSpeed: Double
    public var jumpVelocity: Double
    /// Multiplies the damage the hero deals.
    public var power: Double
    /// Multiplies the damage the hero takes.
    public var toughness: Double
    /// Reach of the hero's normal attacks relative to their class.
    public var reach: Double
    /// Height relative to an average fighter (drawing and boxes).
    public var stature: Double
}

public struct Hero: Identifiable, Equatable, Sendable {
    public let id: HeroID
    public let name: String
    public let title: String
    public let empire: Empire
    public let archetype: Archetype
    public let special: SpecialKind
    public let specialName: String
    public let specialDescription: String
    public let superName: String
    public let superDescription: String
    public let weapon: String
    public let signature: String
    public let quote: String
    public let intro: String
    public let victory: String
    public let defeat: String
    public let bio: String
    public let stats: HeroStats
    /// Rival whose meeting earns its own line, and the line.
    public let rival: (id: HeroID, line: String)?

    public static func == (lhs: Hero, rhs: Hero) -> Bool { lhs.id == rhs.id }
}

public enum Roster {
    public static let all: [Hero] = HeroID.allCases.map(hero)

    /// Selection order: by empire, then class, so the grid reads as four houses.
    public static let selectOrder: [HeroID] = [
        .gaius, .marcusVarro, .livia,
        .khepri, .meritamun, .nefru,
        .tahmina, .bardiya, .arsames, .atossa,
        .zhaoLin, .weiJian, .meiLin,
    ]

    private static func stats(_ archetype: Archetype, stature: Double = 1, power: Double = 1, toughness: Double = 1, speed: Double = 1, health: Double = 1, reach: Double = 1) -> HeroStats {
        var stats = baseStats(archetype, stature: stature, power: power, toughness: toughness, speed: speed, health: health)
        stats.reach *= reach
        return stats
    }

    private static func baseStats(_ archetype: Archetype, stature: Double, power: Double, toughness: Double, speed: Double, health: Double) -> HeroStats {
        switch archetype {
        case .guardian:
            HeroStats(health: 1100 * health, walkSpeed: 3.0 * speed, dashSpeed: 9.5 * speed, jumpVelocity: 15.5, power: 1.0 * power, toughness: 0.97 * toughness, reach: 1.0, stature: 1.04 * stature)
        case .rider:
            HeroStats(health: 980 * health, walkSpeed: 4.1 * speed, dashSpeed: 12.5 * speed, jumpVelocity: 16.5, power: 1.0 * power, toughness: 1.0 * toughness, reach: 1.1, stature: 1.0 * stature)
        case .archer:
            HeroStats(health: 960 * health, walkSpeed: 3.6 * speed, dashSpeed: 11.0 * speed, jumpVelocity: 17.0, power: 1.0 * power, toughness: 1.0 * toughness, reach: 0.95, stature: 0.97 * stature)
        }
    }

    public static func hero(_ id: HeroID) -> Hero {
        switch id {
        case .gaius:
            Hero(id: id, name: "Gaius Aurelius", title: "The Senator's Son", empire: .rome, archetype: .guardian,
                 special: .counter, specialName: "Shield Wall",
                 specialDescription: "Raises the scutum. Any blow that lands on it is answered with a crushing shield bash.",
                 superName: "The Line Holds", superDescription: "Advances behind the shield and drives the enemy back with five relentless blows.",
                 weapon: "Gladius and scutum", signature: "Scarred Scutum",
                 quote: "I spent my youth proving I was strong enough to serve Rome. I spent the rest of my life deciding what that strength should serve.",
                 intro: "Senator's son, they'll tell you. Find out for yourself.",
                 victory: "Get up. Nobody here is dying for my glory.",
                 defeat: "Again, then. I've been knocked down before.",
                 bio: "A senator's son handed a commission he had not earned, Gaius trained until he deserved it and rose as the officers above him fell. The higher he climbed, the more clearly he saw what Rome's victories cost the people beneath them.",
                 stats: stats(.guardian, toughness: 0.96), rival: (.bardiya, "Fear is a poor shield. I've carried a real one for twenty years."))
        case .zhaoLin:
            Hero(id: id, name: "Zhao Lin", title: "The Last Loyalist", empire: .han, archetype: .archer,
                 special: .volley, specialName: "Repeating Bolts",
                 specialDescription: "Two bolts from the bronze trigger in quick succession.",
                 superName: "Watchtower of Juyan", superDescription: "Holds the line from the tower: a storm of bolts that pins the enemy where they stand.",
                 weapon: "Repeating crossbow", signature: "Bronze Trigger of Juyan",
                 quote: "I was raised to defend the Han Dynasty at all costs. I finally learned that the people are the Han Dynasty.",
                 intro: "Forty paces. Wind from the east. You are within range.",
                 victory: "The garrison rules say to report every victory. I will report that you fought well.",
                 defeat: "I counted wrong. It will not happen twice.",
                 bio: "Five generations of his family served the Han. He served it with everything he had, until he learned the people are the Han and the court had forgotten them. Offered the title of Emperor, he refused it.",
                 stats: stats(.archer, toughness: 1.0), rival: (.meiLin, "Strategist. I hope your plan accounts for crossbows."))
        case .tahmina:
            Hero(id: id, name: "Tahmina", title: "The Spirit of the Horse", empire: .persia, archetype: .rider,
                 special: .partingShot, specialName: "Parting Shot",
                 specialDescription: "Springs back out of reach and looses an arrow at the pursuer.",
                 superName: "Rakhsh Runs", superDescription: "Calls her stallion and rides through the enemy again and again, bow singing.",
                 weapon: "Steppe-horn bow and knife", signature: "Steppe-Horn Bow",
                 quote: "You cannot force loyalty. You must earn it.",
                 intro: "Stand still if you like. I won't.",
                 victory: "Ha! You ride like a sack of grain.",
                 defeat: "Thrown, then. Every rider is, once.",
                 bio: "A horse-archer of the open grasslands who led riders by earning their trust, never by demanding it. She speaks in saddle metaphors and goes quiet only when Rakhsh or her lost riders come up.",
                 stats: stats(.rider, speed: 1.08, health: 0.96), rival: (.bardiya, "Your soldiers obey you, Bardiya. Mine would follow me. Learn the difference."))
        case .marcusVarro:
            Hero(id: id, name: "Marcus Varro", title: "The Son of Judea", empire: .rome, archetype: .rider,
                 special: .flankingCharge, specialName: "Flanking Charge",
                 specialDescription: "Gallops past the enemy's guard and strikes from behind.",
                 superName: "Silvered Mask", superDescription: "Dons the cavalry mask and rides down the enemy in a charge no line can turn.",
                 weapon: "Cavalry spatha", signature: "Silvered Cavalry Mask",
                 quote: "I have worn the armour of Rome. I have also stood among the people beneath its shadow.",
                 intro: "Let's settle this honestly, and both walk away.",
                 victory: "Well fought. Rome and Judea both would say so.",
                 defeat: "I yield this one. Not the argument.",
                 bio: "A Roman cavalry prefect born to Judea, who has worn Rome's armour and stood among the people beneath its shadow. In Aetheria he swore the Compact of the Four: an army exists to protect its people.",
                 stats: stats(.rider), rival: (.arsames, "Old friend. The Compact doesn't say we can't spar."))
        case .khepri:
            Hero(id: id, name: "Kepri", title: "The Scarab of War", empire: .egypt, archetype: .rider,
                 special: .desertWind, specialName: "Desert Wind",
                 specialDescription: "Dashes in and leaves a cloud of dust that slows anyone caught in it.",
                 superName: "Rising Sun Chariot", superDescription: "The chariot comes thundering out of the dust and runs the enemy down.",
                 weapon: "Khopesh", signature: "Scarab Reins",
                 quote: "The battlefield belongs to the man who knows it better.",
                 intro: "Which way's the wind blowing? Never mind. I know.",
                 victory: "You fought well for someone who's never crossed a desert.",
                 defeat: "Hm. You knew this ground better. Next time I'll learn it first.",
                 bio: "A wiry chariot scout who thinks in roads, wells, wheels and days of water. Friendly, practical, full of questions, and plain about hard truths.",
                 stats: stats(.rider, speed: 1.06, health: 0.97), rival: (.nefru, "Highness. I scouted this ground for you once. Don't expect the same favour."))
        case .bardiya:
            Hero(id: id, name: "Bardiya", title: "The Fist of Persia", empire: .persia, archetype: .guardian,
                 special: .armoredAdvance, specialName: "Ten Thousand Stand",
                 specialDescription: "Marches forward through blows that would stop any lesser man, then drives his spear home.",
                 superName: "The Immortals", superDescription: "The ten thousand stand behind him. Every spear strikes as one.",
                 weapon: "Spear and wicker shield", signature: "Wicker Shield of the Guard",
                 quote: "Mercy creates weakness. Fear creates obedience. And obedience creates an empire.",
                 intro: "Kneel now and save us both the effort.",
                 victory: "Remember this. Fear is a teacher too.",
                 defeat: "Enjoy it. It will not be repeated.",
                 bio: "A general of the Persian guard who trusts only power and results, openly contemptuous of softness and of Atossa. His rival kingdom and his feud with her are the stuff of Aetheria's border wars.",
                 stats: stats(.guardian, stature: 1.08, power: 0.98, speed: 0.92, health: 1.0, reach: 1.15), rival: (.atossa, "Atossa. Your soft heart will be the end of Persia. Let me end it first."))
        case .weiJian:
            Hero(id: id, name: "Wei Jian", title: "The Survivor of the Han", empire: .han, archetype: .guardian,
                 special: .ironFormation, specialName: "Iron Formation",
                 specialDescription: "Plants his feet and rallies: a shockwave close by, then a long spell of hardened defence.",
                 superName: "Red General's Seal", superDescription: "Stamps the seal of command: a whirl of the jian that ends with the enemy thrown down.",
                 weapon: "Jian", signature: "Red General's Seal",
                 quote: "A kingdom is strongest when its people no longer fear the armies meant to protect them.",
                 intro: "Know the ground. Know yourself. Begin.",
                 victory: "Glory is a poor reason to fight. You fought for a better one, I hope.",
                 defeat: "The terrain favoured you. I should have seen it.",
                 bio: "A Han general who survived the fall of everything he served and kept his word to the villages anyway. Terse, exact, distrustful of glory. One of the Four who swore the Compact.",
                 stats: stats(.guardian, speed: 1.04), rival: (.zhaoLin, "Zhao Lin. Your watchtower held longer than mine. Show me how."))
        case .meritamun:
            Hero(id: id, name: "Meritamun", title: "The Keeper of Balance", empire: .egypt, archetype: .archer,
                 special: .eyeOfHorus, specialName: "Eye of Horus",
                 specialDescription: "A slow orb of sunlight. Whoever it touches is marked and takes more damage for a time.",
                 superName: "Scales of Ma'at", superDescription: "Weighs the enemy's heart. Light falls in a pillar on wherever they stand.",
                 weapon: "Sistrum and sun-staff", signature: "Sistrum of Karnak",
                 quote: "I do not seek to rule the world. I seek to keep it from falling into chaos.",
                 intro: "The river rises whether we fight or not. Shall we?",
                 victory: "The scales settle. Rest now.",
                 defeat: "A dream warned me of this. I did not listen.",
                 bio: "High Priestess of Amun who keeps the balance between kingdoms with omens, grain ledgers and an army she would rather not use. She answers questions with questions.",
                 stats: stats(.archer, toughness: 0.98, health: 1.04, reach: 1.18), rival: (.livia, "Lady Livia. Rome's balance and mine are not the same scale."))
        case .arsames:
            Hero(id: id, name: "Arsamis", title: "The Persian Strategist", empire: .persia, archetype: .rider,
                 special: .levy, specialName: "Satrap's Levy",
                 specialDescription: "Calls a cavalryman of the borderland levy, who rides in from behind and runs the enemy down.",
                 superName: "Golden Rhyton", superDescription: "Raises the rhyton of tribute and the whole levy answers, wave after wave.",
                 weapon: "Akinaka sword", signature: "Golden Rhyton of Tribute",
                 quote: "An empire that wins every battle and creates endless enemies has mastered war, not victory.",
                 intro: "Before we start: what do you plan to do after you win?",
                 victory: "Good. Now, terms. I'm sure we can both live with them.",
                 defeat: "Hm. A battle lost, not a war. Let's talk.",
                 bio: "A borderland strategist who thinks aloud about alliances, supply and who benefits, and mistrusts rulers who treat borderlands like pieces on a board. One of the Four who swore the Compact.",
                 stats: stats(.rider, toughness: 0.98), rival: (.marcusVarro, "Marcus. Shall we see whose cavalry the Compact really runs on?"))
        case .livia:
            Hero(id: id, name: "Livia Drusilla", title: "Voice of Rome", empire: .rome, archetype: .guardian,
                 special: .imperialResolve, specialName: "Imperial Resolve",
                 specialDescription: "A moment of composure: restores some health and strengthens her blows for a time.",
                 superName: "Laurel of Concord", superDescription: "The eagle standard comes down like a verdict, again and again.",
                 weapon: "Eagle standard", signature: "Laurel of Concord",
                 quote: "I have seen what Rome does when it cannot agree. Everything I have done since was so that it would never have to.",
                 intro: "Let us be brief.",
                 victory: "Agreement, at last.",
                 defeat: "Noted.",
                 bio: "Wife of Augustus and mother of Tiberius, who spent a lifetime making sure Rome would never again tear itself apart. In Aetheria her counsel is measured, formal and dry, and she never wastes a word.",
                 stats: stats(.guardian, power: 1.02, speed: 1.02, health: 0.98, reach: 1.18), rival: (.atossa, "Queen Atossa. Two empires, one conversation. Shall we have it?"))
        case .nefru:
            Hero(id: id, name: "Nefru", title: "The Daughter of Kush", empire: .egypt, archetype: .archer,
                 special: .sunlitVolley, specialName: "Sunlit Volley",
                 specialDescription: "Arrows loosed high into the sun fall on the enemy a moment later.",
                 superName: "Bow of the South", superDescription: "Draws the great golden bow of Kush. One shot, and it goes through everything.",
                 weapon: "Golden bow", signature: "Solar Bow of Ra",
                 quote: "My blood gives me a name. What I protect will decide whether that name deserves to be remembered.",
                 intro: "I am not an ornament. You are about to learn that.",
                 victory: "Kush remembers its archers. You will too.",
                 defeat: "Take it, then. I'll be back for it.",
                 bio: "A royal archer of Kush, fiercely proud of her ancestors and the southern lands, warm with people she likes and cold to anyone who treats her as ornament. One of the Four who swore the Compact.",
                 stats: stats(.archer, power: 1.03), rival: (.khepri, "Kepri. You still owe me for the chariot."))
        case .atossa:
            Hero(id: id, name: "Atossa", title: "The Mother of Persia", empire: .persia, archetype: .rider,
                 special: .royalCharge, specialName: "Royal Charge",
                 specialDescription: "Rides the white horse straight through the enemy's blows and throws them into the air.",
                 superName: "House of Cyrus", superDescription: "The royal guard charges behind her banner and nothing stands in front of it.",
                 weapon: "Royal lance", signature: "Diadem of the Royal Road",
                 quote: "I do not fight for the crown. The crown exists for the people.",
                 intro: "Stand aside, or stand against me. Choose quickly.",
                 victory: "Get up. Persia has room for you yet.",
                 defeat: "The people will forgive me this. Will you?",
                 bio: "Daughter of Cyrus the Great, who speaks with the authority of his house and the warmth of someone responsible for thousands. She judges every plan by whether people will be safer for it.",
                 stats: stats(.rider, stature: 1.02, toughness: 0.96, speed: 0.96, health: 1.04, reach: 1.12), rival: (.bardiya, "Bardiya. Fear made you a general. It will not make you a king."))
        case .meiLin:
            Hero(id: id, name: "Mei Lin", title: "The Archer of a Thousand Plans", empire: .han, archetype: .archer,
                 special: .stratagem, specialName: "Thousand Bolt Stratagem",
                 specialDescription: "A gust from the iron fan, and a seal set under the enemy's feet that bursts a moment later.",
                 superName: "The Thousandth Plan", superDescription: "Every seal she ever set goes off at once.",
                 weapon: "Iron fan and repeating crossbow", signature: "Jade Tally of Command",
                 quote: "For years, they used my ideas and remembered their names. Now I will build something they cannot erase.",
                 intro: "I have already played this game. You are three moves behind.",
                 victory: "Remember whose plan that was.",
                 defeat: "Interesting. I will need a thousand and one.",
                 bio: "A court strategist who watched lesser men take credit for her plans for years. She thinks in weiqi and the military classics, plans three moves ahead, and always notes whose idea something was.",
                 stats: stats(.archer, speed: 1.04), rival: (.zhaoLin, "Zhao Lin. You count arrows. I count you."))
        }
    }
}
