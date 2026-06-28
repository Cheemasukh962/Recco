import SwiftUI

/// A compact, tactical scan timeline shown inside the hologram panel while an
/// identity resolution runs. Each stage has a dot (pending / active / done /
/// failed) and a status label. Alive but quiet — only the active row animates.
struct ScanTimelineView: View {
    var stage: ARScanStage
    /// If the scan failed at a particular stage, mark it red.
    var failedStage: ARScanStage? = nil
    var accent: Color = ARTheme.scan

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(ARScanStage.timeline, id: \.self) { s in
                StageRow(stage: s, status: status(for: s), accent: accent)
            }
        }
    }

    private func status(for s: ARScanStage) -> ARStageStatus {
        if let failedStage, s == failedStage { return .failed }
        if s < stage { return .done }
        if s == stage { return .active }
        return .pending
    }
}

/// One timeline row: status dot + title.
private struct StageRow: View {
    let stage: ARScanStage
    let status: ARStageStatus
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            StageDot(status: status, accent: accent)
            Text(stage.title)
                .font(.caption.weight(status == .active ? .semibold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            if status == .active {
                Image(systemName: stage.icon)
                    .font(.caption2)
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: status)
    }

    private var titleColor: Color {
        switch status {
        case .active:  return ARTheme.textPrimary
        case .done:    return ARTheme.textSecondary
        case .pending: return ARTheme.textTertiary
        case .failed:  return ARTheme.danger
        }
    }
}

/// The status dot: hollow (pending), pulsing ring (active), check (done), x (failed).
private struct StageDot: View {
    let status: ARStageStatus
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch status {
            case .pending:
                Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.4)
            case .active:
                Circle()
                    .stroke(accent.opacity(0.4), lineWidth: 1.5)
                    .scaleEffect(pulse && !reduceMotion ? 1.55 : 1.0)
                    .opacity(pulse && !reduceMotion ? 0 : 1)
                Circle().fill(accent)
                    .frame(width: 7, height: 7)
            case .done:
                Circle().fill(accent.opacity(0.22))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accent)
            case .failed:
                Circle().fill(ARTheme.danger.opacity(0.22))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ARTheme.danger)
            }
        }
        .frame(width: 16, height: 16)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: status) { _, _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        guard status == .active, !reduceMotion else { return }
        pulse = false
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        ScanTimelineView(stage: .searching)
            .padding()
            .frame(width: 220)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
    }
    .ignoresSafeArea()
}
#endif
