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
