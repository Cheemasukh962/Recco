import SwiftUI

/// Visual language for the AR intelligence lens. A small, self-contained palette
/// and a reusable "liquid glass" surface so every hologram element reads the same
/// over a live, unpredictable camera feed.
///
/// Design intent (premium AR lens, *not* JARSIS/Iron Man branding):
/// - greyish translucent glass, soft inner stroke + thin accent highlight
/// - cyan = scanning, green = verified, amber = possible, red/orange = error
/// - readable text over camera (a dark tint sits under the material)
/// - 8–14px corner radius — tactical, not bubbly
enum ARTheme {

    // MARK: - Accents

    /// Primary scan accent (cyan/white).
    static let scan = Color(red: 0.40, green: 0.84, blue: 0.99)
    /// Verified match (calm green).
    static let verified = Color(red: 0.38, green: 0.87, blue: 0.58)
    /// Possible / tentative (amber).
    static let possible = Color(red: 0.99, green: 0.76, blue: 0.36)
    /// Errors only (warm red/orange).
    static let danger = Color(red: 0.98, green: 0.50, blue: 0.42)
    /// Calm neutral for "not found" / dim states.
    static let neutral = Color.white

    // MARK: - Brackets

    static let bracketActive = Color.white
    static let bracketActiveGlow = scan
    static let bracketIdle = Color.white.opacity(0.42)

    // MARK: - Text (over camera / glass)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.46)

    // MARK: - Surface

    /// Dark tint under the blur so text stays legible over a bright feed.
    static let panelTint = Color(red: 0.04, green: 0.06, blue: 0.08)
    static let panelCorner: CGFloat = 13
    static let chipCorner: CGFloat = 9
}

/// The reusable hologram surface: frosted material + readability tint + soft
/// inner stroke + a thin accent highlight + a faint top-left specular shine.
/// `accent` tints the highlight/glow so a panel can shift cyan → green → amber
/// as its state changes.
struct HologramSurface: ViewModifier {
    var corner: CGFloat = ARTheme.panelCorner
    var accent: Color = ARTheme.scan
    var glow: Bool = true
    var tintOpacity: Double = 0.55

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(ARTheme.panelTint.opacity(tintOpacity), in: shape)
            .overlay {
                // Subtle top-left specular shine.
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), .clear],
                            startPoint: .topLeading, endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .overlay {
                // Soft inner stroke.
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                // Thin accent highlight along the lit edge.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.75), accent.opacity(0.10), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.42), radius: 16, y: 9)
            .shadow(color: glow ? accent.opacity(0.22) : .clear, radius: 14)
    }
}

/// A small frosted chip (status pills, stage dots' labels).
struct HologramChip: ViewModifier {
    var accent: Color = ARTheme.scan
    func body(content: Content) -> some View {
        content
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))
    }
}

extension View {
    /// Apply the reusable liquid-glass hologram surface.
    func hologramSurface(
        corner: CGFloat = ARTheme.panelCorner,
        accent: Color = ARTheme.scan,
        glow: Bool = true,
        tintOpacity: Double = 0.55
    ) -> some View {
        modifier(HologramSurface(corner: corner, accent: accent, glow: glow, tintOpacity: tintOpacity))
    }

    func hologramChip(accent: Color = ARTheme.scan) -> some View {
        modifier(HologramChip(accent: accent))
    }
}

/// A thin moving highlight used *only while scanning* to imply live activity.
/// Respects Reduce Motion (renders a static faint line instead of sweeping).
struct ScanShimmer: View {
    var accent: Color = ARTheme.scan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [.clear, accent.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: w * 0.45)
            .offset(x: reduceMotion ? w * 0.275 : phase * w)
            .opacity(reduceMotion ? 0.4 : 1)
            .blendMode(.plusLighter)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
        .allowsHitTesting(false)
    }
}
