import Foundation

/// Fully offline backend for `mockAll` (and the deterministic-CV half of
/// `mockCV`). Uses the bundled roster plus the on-device `CommandInterpreter`
/// and `OpenerGenerator`. Adds a tiny artificial delay so the "thinking" state
/// is visible in the demo, but never depends on the network.
final class MockBackend: ReccoBackend {
    private let people: [PersonDTO]
    private let peopleById: [String: PersonDTO]
    /// Simulated round-trip latency for thinking-state visibility.
    private let latency: Duration
    /// In-memory Brain store so the offline demo shows a populated event memory.
    private let memoryStore: MockMemoryStore

    init(people: [PersonDTO], latency: Duration = .milliseconds(450)) {
        self.people = people
        self.peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        self.latency = latency
        self.memoryStore = MockMemoryStore(seedPeople: people)
    }

    func listPeople() async throws -> [PersonDTO] {
        people
    }

    func interpretCommand(transcript: String, visiblePersonIds: [String]) async throws -> FilterCommandDTO {
        try? await Task.sleep(for: latency)
        return CommandInterpreter.interpret(transcript, people: people)
    }

    func createOpener(personId: String, userGoal: String?) async throws -> DraftResultDTO {
        guard let person = peopleById[personId] else {
            throw BackendError.unknownPerson(personId)
        }
        try? await Task.sleep(for: latency)
        return OpenerGenerator.draft(for: person, userGoal: userGoal)
    }

    func matchFace(imageBase64: String, imageMimeType: String, trackId: String) async throws -> FaceMatchResultDTO {
        // Deterministic demo match: hash the trackId onto a roster person so the
        // same track always resolves to the same person (stable overlays).
        try? await Task.sleep(for: .milliseconds(200))
        guard !people.isEmpty else {
            return FaceMatchResultDTO(trackId: trackId, status: .noFace)
        }
        let index = abs(trackId.hashValue) % people.count
        let person = people[index]
        return FaceMatchResultDTO(
            trackId: trackId,
            status: .matched,
            personId: person.id,
            score: 0.44,
            quality: FaceQualityDTO(faceDetected: true, detectionScore: 0.97, cropWidth: 180, cropHeight: 180, model: "mock"),
            message: "deterministic demo match",
            latencyMs: 200
        )
    }

    func resolveIdentity(
        transcript: String,
        trackId: String,
        faceImageBase64: String,
        contextImageBase64: String
    ) async throws -> IdentityResolveResultDTO {
        // Deterministic demo identity: hash the trackId onto a roster person and
        // present a fully-formed candidate so the demo shows the complete flow
        // with no backend. CRITICAL: mock mode has no real CV, so we return
        // `.possible` (never `.verified`) — the app must never claim a verified
        // face match without a real CV embedding (the live path on a device
        // returns `.verified`).
        try? await Task.sleep(for: latency)
        guard !people.isEmpty else {
            return IdentityResolveResultDTO(
                trackId: trackId,
                status: .notFound,
                message: "No roster loaded."
            )
        }
        let index = abs(trackId.hashValue) % people.count
        let person = people[index]
        let candidate = IdentityCandidateDTO(
            candidateId: "cand_mock_\(person.id)",
            fullName: person.name,
            headline: "\(person.role) at \(person.company)",
            role: person.role,
            company: person.company,
            location: nil,
            linkedinUrl: person.links.linkedin,
            email: nil,
            profilePhotoUrl: person.avatarUrl,
            source: "mock",
            matchScore: 0.62
        )
        let verification = FaceVerificationDTO(
            candidateId: candidate.candidateId,
            verified: false,
            score: nil,
            threshold: 0.32,
            faceDetected: false,
            message: "Mock mode: CV unavailable — face not verified."
        )
        let clue = IdentityClueDTO(
            rawText: "\(person.name) · \(person.company)",
            fullName: person.name,
            company: person.company,
            role: person.role,
            confidence: 0.88,
            evidence: "demo badge"
        )
        return IdentityResolveResultDTO(
            trackId: trackId,
            status: .possible,
            clue: clue,
            candidates: [candidate],
            bestCandidate: candidate,
            verification: verification,
            message: "Possible match (demo): \(person.name) · \(person.company). Face not verified in mock mode.",
            latencyMs: 200
        )
    }

    // MARK: - Brain scan memory (offline)

    func listScanMemories() async throws -> [ScanMemoryDTO] {
        memoryStore.list()
    }

    func upsertScanMemory(_ input: ScanMemoryInputDTO) async throws -> ScanMemoryDTO {
        try? await Task.sleep(for: .milliseconds(150))
        return memoryStore.upsert(input)
    }

    func updateScanMemoryNotes(id: String, notes: String?) async throws -> ScanMemoryDTO? {
        memoryStore.updateNotes(id: id, notes: notes)
    }

    func generateScanMemoryOutreach(
        id: String,
        eventName: String?,
        senderName: String?
    ) async throws -> OutreachDraftDTO {
        try? await Task.sleep(for: latency)
        return memoryStore.generateOutreach(id: id, eventName: eventName, senderName: senderName)
    }
}

/// Thread-safe in-memory Brain store for the offline (`mockAll`) backend. Seeded
/// with a few demo memories from the roster so the Brain is demoable with no
/// network; `RECCO_BRAIN_EMPTY=1` starts it empty (for the empty-state demo).
/// Marked `@unchecked Sendable` because all access is guarded by `lock`.
private final class MockMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var memories: [ScanMemoryDTO]

    init(seedPeople people: [PersonDTO]) {
        if ProcessInfo.processInfo.environment["RECCO_BRAIN_EMPTY"] == "1" {
            memories = []
        } else {
            memories = MockMemoryStore.seed(from: people)
        }
    }

    func list() -> [ScanMemoryDTO] {
        lock.lock(); defer { lock.unlock() }
        return memories.sorted { $0.lastScannedAt > $1.lastScannedAt }
    }

    func updateNotes(id: String, notes: String?) -> ScanMemoryDTO? {
        lock.lock(); defer { lock.unlock() }
        guard let i = memories.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        memories[i] = memories[i].replacingNotes((trimmed?.isEmpty == false) ? trimmed : nil)
        return memories[i]
    }

    func generateOutreach(id: String, eventName: String?, senderName: String?) -> OutreachDraftDTO {
        lock.lock(); defer { lock.unlock() }
        let draft: OutreachDraftDTO
        if let i = memories.firstIndex(where: { $0.id == id }) {
            draft = MockMemoryStore.outreach(for: memories[i], eventName: eventName, senderName: senderName)
            memories[i] = memories[i].replacingOutreach(draft)
        } else {
            draft = MockMemoryStore.outreach(for: nil, eventName: eventName, senderName: senderName)
        }
        return draft
    }

    func upsert(_ input: ScanMemoryInputDTO) -> ScanMemoryDTO {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSince1970 * 1000
        let linkedinKey = MockMemoryStore.normalizeLinkedIn(input.linkedinUrl)
        let nameKey = MockMemoryStore.nameCompanyKey(input.name, input.company)

        let index = memories.firstIndex { existing in
            if let lk = linkedinKey, MockMemoryStore.normalizeLinkedIn(existing.linkedinUrl) == lk { return true }
            if let nk = nameKey, MockMemoryStore.nameCompanyKey(existing.name, existing.company) == nk { return true }
            return false
        }

        let confidence = MockMemoryStore.confidence(from: input.status)
        var sources = Set<String>()
        if (input.badgeText?.isEmpty == false) { sources.insert("badge") }
        if input.candidateCount > 0 { sources.insert("fiber") }
        if input.hadFaceVerification { sources.insert("face") }
        if (input.transcript?.isEmpty == false) { sources.insert("voice") }
        if input.personId != nil { sources.insert("roster") }

        if let i = index {
            let prev = memories[i]
            let merged = ScanMemoryDTO(
                id: prev.id,
                scanId: input.scanId,
                personId: input.personId ?? prev.personId,
                name: input.name ?? prev.name,
                headline: input.headline ?? prev.headline,
                role: input.role ?? prev.role,
                company: input.company ?? prev.company,
                school: input.school ?? prev.school,
                linkedinUrl: input.linkedinUrl ?? prev.linkedinUrl,
                email: input.email ?? prev.email,
                confidence: confidence,
                confidenceScore: input.confidenceScore ?? prev.confidenceScore,
                sources: Array(Set(prev.sources).union(sources)).sorted(),
                notes: prev.notes,
                badgeText: input.badgeText ?? prev.badgeText,
                outreach: prev.outreach,
                firstScannedAt: prev.firstScannedAt,
                lastScannedAt: now,
                scanCount: prev.scanCount + 1
            )
            memories[i] = merged
            return merged
        }

        let created = ScanMemoryDTO(
            id: "mem_\(UUID().uuidString.prefix(8))",
            scanId: input.scanId,
            personId: input.personId,
            name: input.name,
            headline: input.headline,
            role: input.role,
            company: input.company,
            school: input.school,
            linkedinUrl: input.linkedinUrl,
            email: input.email,
            confidence: confidence,
            confidenceScore: input.confidenceScore,
            sources: Array(sources).sorted(),
            notes: nil,
            badgeText: input.badgeText,
            outreach: nil,
            firstScannedAt: now,
            lastScannedAt: now,
            scanCount: 1
        )
        memories.append(created)
        return created
    }

    // MARK: - Offline helpers (mirror backend lib/scanMemory + lib/outreach)

    private static func confidence(from status: String) -> ScanConfidence {
        switch status {
        case "verified": return .verified
        case "possible": return .possible
        case "needs_clarification": return .needsConfirmation
        default: return .unknown
        }
    }

    private static func normalizeLinkedIn(_ url: String?) -> String? {
        guard var s = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    private static func nameCompanyKey(_ name: String?, _ company: String?) -> String? {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty else { return nil }
        let c = (company ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return c.isEmpty ? n : "\(n)|\(c)"
    }

    private static func outreach(
        for memory: ScanMemoryDTO?,
        eventName: String?,
        senderName: String?
    ) -> OutreachDraftDTO {
        let fn = memory?.firstName ?? "there"
        let topic = memory?.company ?? memory?.role ?? "what you're building"
        let event = (eventName?.isEmpty == false ? eventName! : "the event")
        let sender = senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let signoff = sender.isEmpty ? "Best" : "Best,\n\(sender)"
        return OutreachDraftDTO(
            linkedinDm: "Hey \(fn), great meeting you at \(event). Loved hearing about \(topic). "
                + "We're building Recco, an AR memory layer for event networking — would love to compare notes.",
            coldEmailSubject: "Great meeting you at \(event)",
            coldEmail: "Hey \(fn),\n\nGreat meeting you at \(event). I noticed you're working around \(topic), "
                + "and it connected with what we're building in Recco: a lightweight AR memory layer for event networking.\n\n"
                + "Would love to compare notes sometime this week.\n\n\(signoff)",
            inPersonOpener: "Hey \(fn) — good to see you again. I was just telling someone about your work on \(topic). "
                + "How's \(event) treating you?"
        )
    }

    private static func seed(from people: [PersonDTO]) -> [ScanMemoryDTO] {
        let now = Date().timeIntervalSince1970 * 1000
        let confidences: [ScanConfidence] = [.verified, .possible, .needsConfirmation]
        let sourceSets = [["badge", "fiber", "face"], ["badge", "fiber", "voice"], ["badge"]]
        return people.prefix(3).enumerated().map { idx, p in
            let linkedin = p.links.linkedin
                ?? "https://www.linkedin.com/in/\(p.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            return ScanMemoryDTO(
                id: "mem_seed_\(p.id)",
                scanId: "trk_seed_\(idx)",
                personId: p.id,
                name: p.name,
                headline: "\(p.role) at \(p.company)",
                role: p.role,
                company: p.company,
                school: nil,
                linkedinUrl: confidences[idx] == .needsConfirmation ? nil : linkedin,
                email: idx == 0 ? "\(p.firstName.lowercased())@\(p.company.lowercased().replacingOccurrences(of: " ", with: "")).com" : nil,
                confidence: confidences[idx],
                confidenceScore: [0.91, 0.74, 0.38][idx],
                sources: sourceSets[idx],
                notes: nil,
                badgeText: "\(p.name) · \(p.company)",
                outreach: nil,
                firstScannedAt: now - Double((idx + 1) * 1000 * 60 * 7),
                lastScannedAt: now - Double(idx * 1000 * 60 * 3),
                scanCount: [3, 1, 1][idx]
            )
        }
    }
}
