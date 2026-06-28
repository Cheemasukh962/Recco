import SwiftUI

/// Detail sheet for a saved scan: contact links, scan context, notes, and
/// generated outreach. Opened from a list row *or* a graph node tap. It reads
/// the memory from `AppModel` by id so notes/outreach updates re-render without
/// dismissing the sheet — and so the graph behind it keeps its layout/selection.
struct BrainMemoryDetailView: View {
    @Environment(AppModel.self) private var appModel
    let memoryId: String

    @State private var notesDraft = ""
    @State private var didSeedNotes = false
    @State private var copiedLabel: String?

    private var memory: ScanMemoryDTO? { appModel.memory(id: memoryId) }

    var body: some View {
        ScrollView {
            if let memory {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(memory)
                    contactSection(memory)
                    sourceSection(memory)
                    notesSection(memory)
                    outreachSection(memory)
                    if let error = appModel.brainError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }
                .padding(20)
                .onAppear { seedNotes(memory) }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                    Text("Memory not found")
                        .font(.headline)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .background(Theme.bg.opacity(0.45))
    }

    private func detailHeader(_ memory: ScanMemoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let line = memory.roleCompanyLine {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let school = clean(memory.school) {
                        Label(school, systemImage: "graduationcap")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let headline = clean(memory.headline), headline != memory.roleCompanyLine {
                        Text(headline)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                ConfidencePill(confidence: memory.confidence)
            }

            HStack(spacing: 8) {
                Label("\(memory.scanCount)x", systemImage: "viewfinder")
                Text(memory.lastScannedDate, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .glassCard(corner: 16)
    }

    @ViewBuilder private func contactSection(_ memory: ScanMemoryDTO) -> some View {
        let links = contactLinks(memory)
        if !links.isEmpty {
            section("Links") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(links, id: \.label) { item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                Label(item.label, systemImage: item.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .glassCard(corner: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sourceSection(_ memory: ScanMemoryDTO) -> some View {
        section("Scan context") {
            VStack(alignment: .leading, spacing: 10) {
                if !memory.sources.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(memory.sources, id: \.self) { source in
                            Text(source.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                    }
                }
                if let badge = clean(memory.badgeText) {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                }
                if let score = memory.confidenceScore {
                    Text("Confidence \(Int((score * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func notesSection(_ memory: ScanMemoryDTO) -> some View {
        section("Notes") {
            VStack(spacing: 10) {
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )

                Button {
                    Task { await appModel.updateMemoryNotes(id: memory.id, notes: notesDraft) }
                } label: {
                    Label("Save notes", systemImage: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.textSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func outreachSection(_ memory: ScanMemoryDTO) -> some View {
        section("Outreach") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await appModel.generateOutreach(memoryId: memory.id) }
                } label: {
                    HStack {
                        if appModel.isGeneratingOutreach {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(memory.outreach == nil ? "Generate outreach" : "Regenerate outreach")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(appModel.isGeneratingOutreach)

                if let draft = memory.outreach {
                    outreachCard("LinkedIn DM", text: draft.linkedinDm)
                    outreachCard("Cold email", subtitle: draft.coldEmailSubject, text: draft.coldEmail)
                    outreachCard("In-person opener", text: draft.inPersonOpener)
                } else {
                    Text("Generate a short LinkedIn DM, cold email, and in-person opener from this scan.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func outreachCard(_ title: String, subtitle: String? = nil, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = [subtitle, text].compactMap { $0 }.joined(separator: "\n\n")
                    withAnimation(.easeOut(duration: 0.15)) { copiedLabel = title }
                } label: {
                    Image(systemName: copiedLabel == title ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Copy \(title)")
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .glassCard(corner: 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contactLinks(_ memory: ScanMemoryDTO) -> [(label: String, icon: String, url: String)] {
        var links: [(String, String, String)] = []
        if let linkedin = clean(memory.linkedinUrl) {
            links.append(("LinkedIn", "person.crop.square", linkedin))
        }
        if let email = clean(memory.email) {
            links.append(("Email", "envelope", "mailto:\(email)"))
        }
        return links
    }

    private func seedNotes(_ memory: ScanMemoryDTO) {
        guard !didSeedNotes else { return }
        notesDraft = memory.notes ?? ""
        didSeedNotes = true
    }

    private func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
