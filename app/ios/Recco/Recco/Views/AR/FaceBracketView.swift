import SwiftUI

/// Thin AR-style corner brackets drawn around a detected face — never a filled
/// box over the face. Non-target faces read as faint grey; the active target is
/// bright white with a soft cyan glow that gently pulses.
struct FaceBracketView: View {
    /// Face rect already mapped into view space (see `FaceOverlayGeometry`).
    let frame: CGRect
    var isActive: Bool
    var accent: Color = ARTheme.bracketActiveGlow

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    private var armLength: CGFloat {
        // Arms scale with the face but stay within a tasteful range.
        let base = min(frame.width, frame.height) * 0.26
        return min(max(base, 14), isActive ? 30 : 22)
    }

    var body: some View {
        ZStack {
            if isActive {
                CornerBrackets(length: armLength)
                    .stroke(accent, style: bracketStroke(width: 3.4))
                    .blur(radius: 6)
                    .opacity(glow ? 0.85 : 0.4)
            }
            CornerBrackets(length: armLength)
                .stroke(isActive ? ARTheme.bracketActive : ARTheme.bracketIdle,
                        style: bracketStroke(width: isActive ? 2.6 : 1.4))
        }
        .frame(width: frame.width, height: frame.height)
        .opacity(isActive ? 1 : 0.85)
        .position(x: frame.midX, y: frame.midY)
        .onAppear { startGlow() }
        .onChange(of: isActive) { _, _ in startGlow() }
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .allowsHitTesting(false)
    }

    private func bracketStroke(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private func startGlow() {
        guard isActive, !reduceMotion else { glow = false; return }
        glow = false
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}

/// Four L-shaped corner marks (top-left, top-right, bottom-right, bottom-left).
struct CornerBrackets: Shape {
    var length: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len = min(length, min(rect.width, rect.height) * 0.45)
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        FaceBracketView(frame: CGRect(x: 60, y: 120, width: 140, height: 170), isActive: false)
        FaceBracketView(frame: CGRect(x: 220, y: 360, width: 150, height: 185), isActive: true)
    }
    .ignoresSafeArea()
}
#endif
