import Foundation

/// What the user is "here for today". Mirrors the backend `GoalType`. Decodes
/// leniently — any unrecognized string becomes `.other` so a new backend value
/// never crashes the app.
enum MissionGoalType: String, Codable, Hashable, CaseIterable {
    case fundraising
    case hiring
    case getHired = "get_hired"
    case customers
    case sponsors
    case cofounder
    case founders
    case networking
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MissionGoalType(rawValue: raw) ?? .other
    }

    /// Short human label for the mission pill / chips.
    var label: String {
        switch self {
        case .fundraising: return "Investors"
        case .hiring: return "Hiring"
        case .getHired: return "Get hired"
        case .customers: return "Customers"
        case .sponsors: return "Sponsors"
        case .cofounder: return "Cofounder"
        case .founders: return "Founders"
        case .networking: return "Networking"
        case .other: return "Mission"
        }
    }

    var systemImage: String {
        switch self {
        case .fundraising: return "dollarsign.circle"
        case .hiring: return "person.2.badge.plus"
        case .getHired: return "briefcase"
        case .customers: return "cart"
        case .sponsors: return "hands.clap"
        case .cofounder: return "person.2"
        case .founders: return "flame"
        case .networking: return "person.3"
        case .other: return "target"
        }
    }
}

/// Preferred follow-up channel. Mirrors backend `PreferredAction`. Lenient.
enum PreferredAction: String, Codable, Hashable {
    case linkedinDm = "linkedin_dm"
    case coldEmail = "cold_email"
    case inPerson = "in_person"
    case reminder

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PreferredAction(rawValue: raw) ?? .reminder
    }

    var label: String {
        switch self {
        case .linkedinDm: return "LinkedIn DM"
        case .coldEmail: return "Cold email"
        case .inPerson: return "In person"
        case .reminder: return "Reminder"
        }
    }

    var systemImage: String {
        switch self {
        case .linkedinDm: return "bubble.left.and.bubble.right"
        case .coldEmail: return "envelope"
        case .inPerson: return "figure.wave"
        case .reminder: return "bell"
        }
    }
}

/// The structured "Today's Goal". Mirrors the backend `MissionProfile`. Decoding
/// is lenient so a partial payload never crashes; it round-trips to/from
/// UserDefaults and to the backend scan-memory / outreach routes.
struct MissionProfileDTO: Codable, Equatable, Hashable, Identifiable {
    var id: String?
    var clientId: String?
    var rawText: String
    var goalType: MissionGoalType
    var targetRoles: [String]
    var targetKeywords: [String]
    var targetCompanies: [String]
    var targetIndustries: [String]
    var preferredAction: PreferredAction
    var userContext: String?
    var tone: String
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id, clientId, rawText, goalType, targetRoles, targetKeywords
        case targetCompanies, targetIndustries, preferredAction, userContext
        case tone, createdAt, updatedAt
    }

    init(
        id: String? = nil,
        clientId: String? = nil,
        rawText: String,
        goalType: MissionGoalType,
        targetRoles: [String] = [],
        targetKeywords: [String] = [],
        targetCompanies: [String] = [],
        targetIndustries: [String] = [],
        preferredAction: PreferredAction = .reminder,
        userContext: String? = nil,
        tone: String = "warm, concise",
        createdAt: Double = 0,
        updatedAt: Double = 0
    ) {
        self.id = id
        self.clientId = clientId
        self.rawText = rawText
        self.goalType = goalType
        self.targetRoles = targetRoles
        self.targetKeywords = targetKeywords
        self.targetCompanies = targetCompanies
        self.targetIndustries = targetIndustries
        self.preferredAction = preferredAction
        self.userContext = userContext
        self.tone = tone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        rawText = (try? c.decode(String.self, forKey: .rawText)) ?? ""
        goalType = (try? c.decode(MissionGoalType.self, forKey: .goalType)) ?? .other
        targetRoles = (try? c.decode([String].self, forKey: .targetRoles)) ?? []
        targetKeywords = (try? c.decode([String].self, forKey: .targetKeywords)) ?? []
        targetCompanies = (try? c.decode([String].self, forKey: .targetCompanies)) ?? []
        targetIndustries = (try? c.decode([String].self, forKey: .targetIndustries)) ?? []
        preferredAction = (try? c.decode(PreferredAction.self, forKey: .preferredAction)) ?? .reminder
        userContext = try c.decodeIfPresent(String.self, forKey: .userContext)
        tone = (try? c.decode(String.self, forKey: .tone)) ?? "warm, concise"
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }

    /// Short label for the mission pill ("Investors", or the raw goal trimmed).
    var label: String {
        if goalType == .other {
            let t = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Mission" : String(t.prefix(22))
        }
        return goalType.label
    }

    /// The default mission used when the user skips setup.
    static func networking(now: Double = Date().timeIntervalSince1970 * 1000) -> MissionProfileDTO {
        MissionProfileDTO(
            rawText: "General networking",
            goalType: .networking,
            preferredAction: .inPerson,
            tone: "warm, concise, specific",
            createdAt: now,
            updatedAt: now
        )
    }
}
