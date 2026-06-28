import SwiftUI

/// The tactical scan timeline stages, in order. Driven by `CameraViewModel`
/// while an identity resolution is in flight; the last stage flips to the result
/// view. These are presentation stages — the backend lane stays a single call.
enum ARScanStage: Int, CaseIterable, Comparable {
    case locked          // face locked as the target
    case readingBadge    // OCR'ing the name tag / context
    case searching       // looking up candidate profiles
    case verifying       // face-verifying the best candidate
    case result          // done — show the result

    static func < (lhs: ARScanStage, rhs: ARScanStage) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .locked:       return "Face locked"
        case .readingBadge: return "Reading badge"
        case .searching:    return "Searching profile"
        case .verifying:    return "Verifying face"
        case .result:       return "Result ready"
        }
    }

    var icon: String {
        switch self {
        case .locked:       return "scope"
        case .readingBadge: return "text.viewfinder"
        case .searching:    return "person.text.rectangle"
        case .verifying:    return "faceid"
        case .result:       return "sparkles"
        }
    }

    /// The stages shown as a timeline (everything up to, and including, result).
    static let timeline: [ARScanStage] = [.locked, .readingBadge, .searching, .verifying, .result]
}

/// Per-row status in the scan timeline.
enum ARStageStatus {
    case pending, active, done, failed
}

/// Adapter that turns an `IdentityResolveResultDTO` (the real backend result, or
/// a mock one) into display-ready fields for the hologram result panel. This is
/// the clean seam the prompt asks for: the panel never touches the DTO directly,
/// so swapping mock ↔ live changes nothing in the view.
struct ARIdentityDisplayModel: Equatable {
    enum Kind { case verified, possible, needsClarification, notFound, error }

    let kind: Kind
    let title: String
    let subtitle: String?
    let badgeText: String
    let badgeIcon: String
    let accent: Color
    /// Short reason / hint / message under the header.
    let detail: String?
    /// Generated conversation opener suggestion, when we can form a good one.
    let opener: String?
    let linkedinURL: URL?
    let candidate: IdentityCandidateDTO?
    /// True when a Retry affordance makes sense (error / unclear).
    let allowsRetry: Bool

    init(result: IdentityResolveResultDTO) {
        let best = result.bestCandidate
        self.candidate = best
        self.linkedinURL = best?.linkedinUrl
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            .flatMap(URL.init(string:))

        switch result.status {
        case .verified:
            kind = .verified
            title = best?.fullName ?? result.clue?.fullName ?? "Verified"
            subtitle = best?.roleCompany
            badgeText = "Verified"
            badgeIcon = "checkmark.seal.fill"
            accent = ARTheme.verified
            detail = result.message
            allowsRetry = false
        case .possible:
            kind = .possible
            title = best?.fullName ?? result.clue?.fullName ?? "Possible match"
            subtitle = best?.roleCompany
            badgeText = "Possible match"
            badgeIcon = "questionmark.circle.fill"
            accent = ARTheme.possible
            detail = ARIdentityDisplayModel.possibleReason(result)
            allowsRetry = false
        case .needsClarification:
            kind = .needsClarification
            title = "Name unclear"
            subtitle = nil
            badgeText = "Move closer"
            badgeIcon = "exclamationmark.bubble.fill"
            accent = ARTheme.possible
            detail = result.message
                ?? "Couldn't read the badge clearly. Point at their name tag or move a little closer."
            allowsRetry = true
        case .notFound:
            kind = .notFound
            title = "No match found"
            subtitle = nil
            badgeText = "No match"
            badgeIcon = "magnifyingglass"
            accent = ARTheme.neutral.opacity(0.7)
            detail = result.message ?? "No public profile matched this badge."
            allowsRetry = true
        case .error:
            kind = .error
            title = "Couldn't resolve"
            subtitle = nil
            badgeText = "Error"
            badgeIcon = "xmark.octagon.fill"
            accent = ARTheme.danger
            detail = result.message ?? "Something went wrong. Try again."
            allowsRetry = true
        }

        self.opener = ARIdentityDisplayModel.makeOpener(for: result)
    }

    /// Direct memberwise init for previews / synthetic states.
    private init(kind: Kind, title: String, subtitle: String?, badgeText: String,
                 badgeIcon: String, accent: Color, detail: String?, opener: String?,
                 linkedinURL: URL?, candidate: IdentityCandidateDTO?, allowsRetry: Bool) {
        self.kind = kind; self.title = title; self.subtitle = subtitle
        self.badgeText = badgeText; self.badgeIcon = badgeIcon; self.accent = accent
        self.detail = detail; self.opener = opener; self.linkedinURL = linkedinURL
        self.candidate = candidate; self.allowsRetry = allowsRetry
    }

    // MARK: - Derived copy

    private static func possibleReason(_ result: IdentityResolveResultDTO) -> String? {
        if let v = result.verification, !v.verified {
            return v.message ?? "Strong text match, but the face wasn't verified."
        }
        return result.message
    }

    /// A short, non-fabricated opener built only from fields we actually have.
    private static func makeOpener(for result: IdentityResolveResultDTO) -> String? {
        guard result.status == .verified || result.status == .possible,
              let c = result.bestCandidate else { return nil }
        let first = c.fullName.split(separator: " ").first.map(String.init) ?? c.fullName
        if let company = c.company, !company.isEmpty {
            return "Ask \(first) what they're building at \(company)."
        }
        if let role = c.role, !role.isEmpty {
            return "Ask \(first) what drew them to \(role.lowercased())."
        }
        if let headline = c.headline, !headline.isEmpty {
            return "Open with their work: “\(headline)”."
        }
        return nil
    }

    // MARK: - Preview / mock states (for SwiftUI previews & frontend review)

    static let previewVerified = ARIdentityDisplayModel(
        kind: .verified, title: "Ava Chen", subtitle: "Founder · Loop AI",
        badgeText: "Verified", badgeIcon: "checkmark.seal.fill", accent: ARTheme.verified,
        detail: "Face verified against their profile photo.",
        opener: "Ask Ava what they're building at Loop AI.",
        linkedinURL: URL(string: "https://linkedin.com/in/example"),
        candidate: nil, allowsRetry: false)

    static let previewPossible = ARIdentityDisplayModel(
        kind: .possible, title: "Marcus Reed", subtitle: "Infra Lead · Vector",
        badgeText: "Possible match", badgeIcon: "questionmark.circle.fill", accent: ARTheme.possible,
        detail: "Strong text match, but the face wasn't verified.",
        opener: "Ask Marcus what they're building at Vector.",
        linkedinURL: URL(string: "https://linkedin.com/in/example"),
        candidate: nil, allowsRetry: false)

    static let previewClarify = ARIdentityDisplayModel(
        kind: .needsClarification, title: "Name unclear", subtitle: nil,
        badgeText: "Move closer", badgeIcon: "exclamationmark.bubble.fill", accent: ARTheme.possible,
        detail: "Couldn't read the badge clearly. Point at their name tag or move a little closer.",
        opener: nil, linkedinURL: nil, candidate: nil, allowsRetry: true)

    static let previewNotFound = ARIdentityDisplayModel(
        kind: .notFound, title: "No match found", subtitle: nil,
        badgeText: "No match", badgeIcon: "magnifyingglass", accent: ARTheme.neutral.opacity(0.7),
        detail: "No public profile matched this badge.",
        opener: nil, linkedinURL: nil, candidate: nil, allowsRetry: true)

    static let previewError = ARIdentityDisplayModel(
        kind: .error, title: "Couldn't resolve", subtitle: nil,
        badgeText: "Error", badgeIcon: "xmark.octagon.fill", accent: ARTheme.danger,
        detail: "Network unavailable. Try again.",
        opener: nil, linkedinURL: nil, candidate: nil, allowsRetry: true)
}
