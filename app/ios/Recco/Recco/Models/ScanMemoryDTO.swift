import Foundation

/// Confidence bucket for a saved scan. Mirrors the backend `ScanConfidence`.
/// Decodes leniently: any unrecognized string becomes `.unknown`.
enum ScanConfidence: String, Codable, Hashable {
    case verified
    case possible
    case needsConfirmation = "needs_confirmation"
    case unknown

    /// Short user-facing label.
    var label: String {
        switch self {
        case .verified: return "Verified"
        case .possible: return "Possible"
        case .needsConfirmation: return "Needs confirm"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .possible: return "questionmark.circle.fill"
        case .needsConfirmation: return "exclamationmark.circle"
        case .unknown: return "person.fill.questionmark"
        }
    }
}

/// A generated outreach draft: three ready-to-send variants. Mirrors the backend
/// `OutreachDraft`.
struct OutreachDraftDTO: Codable, Equatable, Hashable {
    var linkedinDm: String
    var coldEmailSubject: String
    var coldEmail: String
    var inPersonOpener: String
    var generatedAt: Double

    init(
        linkedinDm: String,
        coldEmailSubject: String,
        coldEmail: String,
        inPersonOpener: String,
        generatedAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.linkedinDm = linkedinDm
        self.coldEmailSubject = coldEmailSubject
        self.coldEmail = coldEmail
        self.inPersonOpener = inPersonOpener
        self.generatedAt = generatedAt
    }
}

/// A durable Brain "event memory" — one resolved person, scored against the
/// user's mission. Mirrors the backend public `ScanMemory`. Decoding is
/// deliberately lenient: every uncertain field is optional with a safe default
/// so a partial (or older) backend payload never crashes.
struct ScanMemoryDTO: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let scanId: String
    let personId: String?
    let name: String?
    let headline: String?
    let role: String?
    let company: String?
    let school: String?
    let linkedinUrl: String?
    let email: String?
    let confidence: ScanConfidence
    let confidenceScore: Double?
    let sources: [String]
    var notes: String?
    let badgeText: String?
    var outreach: OutreachDraftDTO?
    let firstScannedAt: Double
    let lastScannedAt: Double
    let scanCount: Int

    // Mission-driven lead scoring + follow-up.
    let clientId: String?
    var leadPriority: LeadPriority?
    var leadScore: Double?
    var leadReasons: [String]
    var nextAction: String?
    var followUpStatus: FollowUpStatus
    var sentAt: Double?
    var editedOutreach: OutreachDraftDTO?
    var missionSnapshot: MissionProfileDTO?

    enum CodingKeys: String, CodingKey {
        case id, scanId, personId, name, headline, role, company, school
        case linkedinUrl, email, confidence, confidenceScore, sources, notes
        case badgeText, outreach, firstScannedAt, lastScannedAt, scanCount
        case clientId, leadPriority, leadScore, leadReasons, nextAction
        case followUpStatus, sentAt, editedOutreach, missionSnapshot
    }

    init(
        id: String,
        scanId: String,
        personId: String? = nil,
        name: String? = nil,
        headline: String? = nil,
        role: String? = nil,
        company: String? = nil,
        school: String? = nil,
        linkedinUrl: String? = nil,
        email: String? = nil,
        confidence: ScanConfidence = .unknown,
        confidenceScore: Double? = nil,
        sources: [String] = [],
        notes: String? = nil,
        badgeText: String? = nil,
        outreach: OutreachDraftDTO? = nil,
        firstScannedAt: Double = 0,
        lastScannedAt: Double = 0,
        scanCount: Int = 1,
        clientId: String? = nil,
        leadPriority: LeadPriority? = nil,
        leadScore: Double? = nil,
        leadReasons: [String] = [],
        nextAction: String? = nil,
        followUpStatus: FollowUpStatus = .new,
        sentAt: Double? = nil,
        editedOutreach: OutreachDraftDTO? = nil,
        missionSnapshot: MissionProfileDTO? = nil
    ) {
        self.id = id
        self.scanId = scanId
        self.personId = personId
        self.name = name
        self.headline = headline
        self.role = role
        self.company = company
        self.school = school
        self.linkedinUrl = linkedinUrl
        self.email = email
        self.confidence = confidence
        self.confidenceScore = confidenceScore
        self.sources = sources
        self.notes = notes
        self.badgeText = badgeText
        self.outreach = outreach
        self.firstScannedAt = firstScannedAt
        self.lastScannedAt = lastScannedAt
        self.scanCount = scanCount
        self.clientId = clientId
        self.leadPriority = leadPriority
        self.leadScore = leadScore
        self.leadReasons = leadReasons
        self.nextAction = nextAction
        self.followUpStatus = followUpStatus
        self.sentAt = sentAt
        self.editedOutreach = editedOutreach
        self.missionSnapshot = missionSnapshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scanId = (try? c.decode(String.self, forKey: .scanId)) ?? id
        personId = try c.decodeIfPresent(String.self, forKey: .personId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        headline = try c.decodeIfPresent(String.self, forKey: .headline)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        company = try c.decodeIfPresent(String.self, forKey: .company)
        school = try c.decodeIfPresent(String.self, forKey: .school)
        linkedinUrl = try c.decodeIfPresent(String.self, forKey: .linkedinUrl)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        let rawConfidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        confidence = rawConfidence.flatMap(ScanConfidence.init(rawValue:)) ?? .unknown
        confidenceScore = try c.decodeIfPresent(Double.self, forKey: .confidenceScore)
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        badgeText = try c.decodeIfPresent(String.self, forKey: .badgeText)
        outreach = try c.decodeIfPresent(OutreachDraftDTO.self, forKey: .outreach)
        firstScannedAt = (try? c.decode(Double.self, forKey: .firstScannedAt)) ?? 0
        lastScannedAt = (try? c.decode(Double.self, forKey: .lastScannedAt)) ?? 0
        scanCount = (try? c.decode(Int.self, forKey: .scanCount)) ?? 1
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        leadPriority = try c.decodeIfPresent(LeadPriority.self, forKey: .leadPriority)
        leadScore = try c.decodeIfPresent(Double.self, forKey: .leadScore)
        leadReasons = (try? c.decode([String].self, forKey: .leadReasons)) ?? []
        nextAction = try c.decodeIfPresent(String.self, forKey: .nextAction)
        followUpStatus = (try? c.decode(FollowUpStatus.self, forKey: .followUpStatus)) ?? .new
        sentAt = try c.decodeIfPresent(Double.self, forKey: .sentAt)
        editedOutreach = try c.decodeIfPresent(OutreachDraftDTO.self, forKey: .editedOutreach)
        missionSnapshot = try c.decodeIfPresent(MissionProfileDTO.self, forKey: .missionSnapshot)
    }

    private func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    // MARK: - Display helpers

    /// Display name, falling back to a neutral label for an info-less scan.
    var displayName: String { clean(name) ?? "Unknown scan" }

    /// "Role · Company" one-liner when available.
    var roleCompanyLine: String? {
        switch (clean(role), clean(company)) {
        case let (r?, c?): return "\(r) · \(c)"
        case let (r?, nil): return r
        case let (nil, c?): return c
        default: return clean(headline)
        }
    }

    var firstName: String {
        guard let name = clean(name) else { return "there" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var hasLinkedIn: Bool { clean(linkedinUrl) != nil }

    var lastScannedDate: Date {
        Date(timeIntervalSince1970: lastScannedAt / 1000)
    }

    // MARK: - Lead helpers

    var priorityLabel: String { leadPriority?.label ?? "Unscored" }

    /// The outreach to show/send: the user's edits win over the generated draft.
    var effectiveOutreach: OutreachDraftDTO? { editedOutreach ?? outreach }

    var isSent: Bool { followUpStatus == .sent }

    var hasOutreach: Bool { effectiveOutreach != nil }

    /// Matches a free-text query against identity *and* lead signal: name,
    /// company, role, headline, linkedin, school, priority label, reasons, and
    /// the mission keywords it was scored under.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        var parts = [name, company, role, headline, linkedinUrl, school, leadPriority?.label]
            .compactMap { $0?.lowercased() }
        parts.append(contentsOf: leadReasons.map { $0.lowercased() })
        if let mission = missionSnapshot {
            parts.append(mission.rawText.lowercased())
            parts.append(mission.goalType.label.lowercased())
        }
        return parts.joined(separator: " ").contains(q)
    }

    // MARK: - Immutable copy helpers

    private func copy(
        notes: String?? = nil,
        outreach: OutreachDraftDTO?? = nil,
        leadPriority: LeadPriority?? = nil,
        leadScore: Double?? = nil,
        leadReasons: [String]? = nil,
        nextAction: String?? = nil,
        followUpStatus: FollowUpStatus? = nil,
        sentAt: Double?? = nil,
        editedOutreach: OutreachDraftDTO?? = nil,
        missionSnapshot: MissionProfileDTO?? = nil
    ) -> ScanMemoryDTO {
        ScanMemoryDTO(
            id: id,
            scanId: scanId,
            personId: personId,
            name: name,
            headline: headline,
            role: role,
            company: company,
            school: school,
            linkedinUrl: linkedinUrl,
            email: email,
            confidence: confidence,
            confidenceScore: confidenceScore,
            sources: sources,
            notes: notes ?? self.notes,
            badgeText: badgeText,
            outreach: outreach ?? self.outreach,
            firstScannedAt: firstScannedAt,
            lastScannedAt: lastScannedAt,
            scanCount: scanCount,
            clientId: clientId,
            leadPriority: leadPriority ?? self.leadPriority,
            leadScore: leadScore ?? self.leadScore,
            leadReasons: leadReasons ?? self.leadReasons,
            nextAction: nextAction ?? self.nextAction,
            followUpStatus: followUpStatus ?? self.followUpStatus,
            sentAt: sentAt ?? self.sentAt,
            editedOutreach: editedOutreach ?? self.editedOutreach,
            missionSnapshot: missionSnapshot ?? self.missionSnapshot
        )
    }

    func replacingNotes(_ notes: String?) -> ScanMemoryDTO {
        copy(notes: .some(notes))
    }

    func replacingOutreach(_ outreach: OutreachDraftDTO?) -> ScanMemoryDTO {
        copy(outreach: .some(outreach))
    }

    func replacingFollowUp(
        status: FollowUpStatus,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) -> ScanMemoryDTO {
        copy(
            followUpStatus: status,
            sentAt: .some(sentAt),
            editedOutreach: .some(editedOutreach)
        )
    }

    func replacingLead(
        priority: LeadPriority?,
        score: Double?,
        reasons: [String],
        nextAction: String?,
        missionSnapshot: MissionProfileDTO?
    ) -> ScanMemoryDTO {
        copy(
            leadPriority: .some(priority),
            leadScore: .some(score),
            leadReasons: reasons,
            nextAction: .some(nextAction),
            missionSnapshot: .some(missionSnapshot)
        )
    }
}

/// Input the app posts to upsert a memory after an identity resolve. Encodable;
/// carries only extracted text/links/scores — never images. Now also carries the
/// `clientId` (Brain isolation) and the current `mission` (triggers scoring).
struct ScanMemoryInputDTO: Encodable {
    let scanId: String
    let status: String
    let clientId: String?
    let mission: MissionProfileDTO?
    let name: String?
    let headline: String?
    let role: String?
    let company: String?
    let school: String?
    let linkedinUrl: String?
    let email: String?
    let confidenceScore: Double?
    let personId: String?
    let transcript: String?
    let badgeText: String?
    let hadFaceVerification: Bool
    let candidateCount: Int
}
