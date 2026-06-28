import SwiftUI

/// A small, unobtrusive center reticle that implies "this is the target zone."
/// The face nearest the center auto-locks, so the reticle quietly explains who
/// "him / this person" refers to. Brightens a touch while a scan is running.
struct TargetReticleView: View {
    /// True while an identity scan is active (slightly brighter + a live dot).
    var active: Bool = false
    var accent: Color = ARTheme.scan

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var lineOpacity: Double { active ? 0.55 : 0.30 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(lineOpacity), lineWidth: 1)
                .frame(width: 36, height: 36)

            // Four short ticks at N/E/S/W.
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(lineOpacity + 0.05))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -24)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
                .opacity(active ? 1 : 0.35)
                .scaleEffect(active && breathe && !reduceMotion ? 1.5 : 1.0)
        }
        .compositingGroup()
        .opacity(active ? 1 : 0.9)
        .allowsHitTesting(false)
        .onChange(of: active) { _, now in
            guard now, !reduceMotion else { breathe = false; return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        TargetReticleView(active: false).position(x: 120, y: 250)
        TargetReticleView(active: true).position(x: 260, y: 450)
    }
    .ignoresSafeArea()
}
#endif
