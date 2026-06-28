import Foundation

/// Lead priority bucket. Mirrors the backend `LeadPriority`. Decodes leniently:
/// an unrecognized value becomes `.needsInfo`.
enum LeadPriority: String, Codable, Hashable, CaseIterable {
    case hot
    case warm
    case cold
    case needsInfo = "needs_info"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LeadPriority(rawValue: raw) ?? .needsInfo
    }

    var label: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .cold: return "Cold"
        case .needsInfo: return "Needs info"
        }
    }

    var systemImage: String {
        switch self {
        case .hot: return "flame.fill"
        case .warm: return "sun.max.fill"
        case .cold: return "snowflake"
        case .needsInfo: return "questionmark.circle"
        }
    }

    /// Stable sort/priority weight (hot first).
    var rank: Int {
        switch self {
        case .hot: return 0
        case .warm: return 1
        case .cold: return 2
        case .needsInfo: return 3
        }
    }
}

/// Where a lead is in the follow-up flow. Mirrors backend `FollowUpStatus`.
/// Decodes leniently to `.new`.
enum FollowUpStatus: String, Codable, Hashable {
    case new
    case drafted
    case edited
    case sent
    case archived

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FollowUpStatus(rawValue: raw) ?? .new
    }

    var label: String {
        switch self {
        case .new: return "New"
        case .drafted: return "Drafted"
        case .edited: return "Edited"
        case .sent: return "Sent"
        case .archived: return "Archived"
        }
    }
}

/// The channel a follow-up was (fake) sent through. Mirrors the backend
/// `followUpChannel` string. Decodes leniently to `.linkedinDm`.
enum FollowUpChannel: String, Codable, Hashable, CaseIterable, Identifiable {
    case linkedinDm = "linkedin_dm"
    case coldEmail = "cold_email"
    case inPerson = "in_person"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FollowUpChannel(rawValue: raw) ?? .linkedinDm
    }

    /// Short label for the segmented selector.
    var tabLabel: String {
        switch self {
        case .linkedinDm: return "LinkedIn"
        case .coldEmail: return "Email"
        case .inPerson: return "In person"
        }
    }

    var systemImage: String {
        switch self {
        case .linkedinDm: return "bubble.left.and.bubble.right.fill"
        case .coldEmail: return "envelope.fill"
        case .inPerson: return "figure.wave"
        }
    }

    /// Channel-specific action button label.
    var sendLabel: String {
        switch self {
        case .linkedinDm: return "Send LinkedIn DM"
        case .coldEmail: return "Send Email"
        case .inPerson: return "Mark opener used"
        }
    }

    /// Past-tense confirmation shown after a (fake) send.
    var sentLabel: String {
        switch self {
        case .linkedinDm: return "Sent · LinkedIn DM"
        case .coldEmail: return "Sent · Email"
        case .inPerson: return "Opener used"
        }
    }

    /// The mission's preferred action maps to a sensible default channel.
    static func from(action: PreferredAction?) -> FollowUpChannel {
        switch action {
        case .linkedinDm: return .linkedinDm
        case .coldEmail: return .coldEmail
        case .inPerson: return .inPerson
        case .reminder, .none: return .linkedinDm
        }
    }
}

/// A computed lead score (the `/api/brain/memories/score` response shape). On a
/// saved memory the fields are flattened onto `ScanMemoryDTO`; this mirrors the
/// backend `LeadScore` for completeness.
struct LeadScoreDTO: Codable, Equatable, Hashable {
    let priority: LeadPriority
    let score: Double
    let reasons: [String]
    let nextAction: String?
    let missingInfo: [String]
    let scoredAt: Double
}
