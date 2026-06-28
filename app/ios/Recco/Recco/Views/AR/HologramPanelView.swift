import SwiftUI
import UIKit

/// The floating liquid-glass hologram panel that "belongs" to the active face.
/// It has two states:
///  - `.scanning` — a compact tactical scan timeline + live shimmer.
///  - `.result`   — the resolved identity (verified / possible / unclear /
///                  not-found / error), driven entirely by `ARIdentityDisplayModel`.
///
/// The panel is a fixed width so the parent can anchor/clamp it deterministically
/// (see `FaceOverlayGeometry.placePanel`). Positioning, the connector line, and
/// the anchor dot are the parent's job — this view only renders content.
struct HologramPanelView: View {
    enum Mode: Equatable {
        case scanning(ARScanStage, failedStage: ARScanStage?)
        case result(ARIdentityDisplayModel)
    }

    let mode: Mode
    var onClose: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDetails: () -> Void = {}

    static let width: CGFloat = 234

    private var accent: Color {
        switch mode {
        case .scanning: return ARTheme.scan
        case .result(let m): return m.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            switch mode {
            case .scanning(let stage, let failed):
                scanningBody(stage: stage, failed: failed)
            case .result(let model):
                resultBody(model)
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .hologramSurface(accent: accent)
        .overlay(alignment: .topTrailing) { closeButton }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height > 36 && value.translation.height > abs(value.translation.width) {
                        onClose()
                    }
                }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: mode)
    }

    // MARK: - Scanning

    private func scanningBody(stage: ARScanStage, failed: ARScanStage?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                LiveDot(accent: ARTheme.scan)
                Text("SCANNING")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(ARTheme.scan)
                Spacer(minLength: 18) // room for the close button
            }

            Text("Identifying…")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ARTheme.textPrimary)

            ScanShimmer(accent: ARTheme.scan)
                .frame(height: 2)
                .clipShape(Capsule())

            ScanTimelineView(stage: stage, failedStage: failed, accent: ARTheme.scan)
        }
    }

    // MARK: - Result

    private func resultBody(_ model: ARIdentityDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Badge
            HStack(spacing: 5) {
                Image(systemName: model.badgeIcon)
                Text(model.badgeText.uppercased())
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(model.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .hologramChip(accent: model.accent)

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ARTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.accent)
                        .lineLimit(2)
                }
            }

            if let detail = model.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ARTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let opener = model.opener {
                openerBlock(opener, accent: model.accent)
            }

            if let url = model.linkedinURL {
                linkedInButton(url: url, accent: model.accent)
            }

            actionRow(model)
        }
    }

    private func openerBlock(_ text: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundStyle(accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(ARTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    private func linkedInButton(url: URL, accent: Color) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                Text("LinkedIn")
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open LinkedIn profile")
    }

    @ViewBuilder
    private func actionRow(_ model: ARIdentityDisplayModel) -> some View {
        HStack(spacing: 8) {
            if model.candidate != nil {
                pillButton(title: "Details", icon: "chevron.right", action: onDetails)
            }
            if model.allowsRetry {
                pillButton(title: "Retry", icon: "arrow.clockwise", action: onRetry)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    private func pillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: icon).font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ARTheme.textPrimary)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Close

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ARTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Dismiss")
    }
}

/// A tiny pulsing "live" dot for the scanning eyebrow.
private struct LiveDot: View {
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion ? 1 : (on ? 1 : 0.3))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

#if DEBUG
#Preview("Scanning") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        HologramPanelView(mode: .scanning(.searching, failedStage: nil))
    }
    .ignoresSafeArea()
}

#Preview("Result · Verified") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        HologramPanelView(mode: .result(.previewVerified))
    }
    .ignoresSafeArea()
}

#Preview("Result · Unclear") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        HologramPanelView(mode: .result(.previewClarify))
    }
    .ignoresSafeArea()
}
#endif
