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
    let linkedinDm: String
    let coldEmailSubject: String
    let coldEmail: String
    let inPersonOpener: String
    let generatedAt: Double

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

/// A durable Brain "event memory" — one resolved person. Mirrors the backend
/// public `ScanMemory`. Decoding is deliberately lenient: every uncertain field
/// is optional with a safe default so a partial backend payload never crashes.
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

    enum CodingKeys: String, CodingKey {
        case id, scanId, personId, name, headline, role, company, school
        case linkedinUrl, email, confidence, confidenceScore, sources, notes
        case badgeText, outreach, firstScannedAt, lastScannedAt, scanCount
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
        scanCount: Int = 1
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

    /// Matches a free-text query against name/company/role/headline/linkedin.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let haystack = [name, company, role, headline, linkedinUrl, school]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return haystack.contains(q)
    }

    /// Copy helper for local/backend updates while keeping the DTO immutable.
    private func copy(notes: String?, outreach: OutreachDraftDTO?) -> ScanMemoryDTO {
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
            notes: notes,
            badgeText: badgeText,
            outreach: outreach,
            firstScannedAt: firstScannedAt,
            lastScannedAt: lastScannedAt,
            scanCount: scanCount
        )
    }

    func replacingNotes(_ notes: String?) -> ScanMemoryDTO {
        copy(notes: notes, outreach: outreach)
    }

    func replacingOutreach(_ outreach: OutreachDraftDTO?) -> ScanMemoryDTO {
        copy(notes: notes, outreach: outreach)
    }
}

/// Input the app posts to upsert a memory after an identity resolve. Encodable;
/// carries only extracted text/links/scores — never images.
struct ScanMemoryInputDTO: Encodable {
    let scanId: String
    let status: String
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
