import SwiftUI
import UIKit

/// The camera-first AR intelligence lens. Fills the screen with the live preview
/// (or the simulated backdrop), draws thin corner brackets on every detected face
/// (bright/glowing for the active target, dim grey for the rest), a small center
/// reticle, and a liquid-glass hologram panel anchored beside the active face that
/// shows the scan sequence and identity result.
///
/// Coordinate handling: the preview renders `.resizeAspectFill`, so face boxes are
/// mapped through `FaceOverlayGeometry.displayRect` (which reproduces the aspect-
/// fill crop) rather than a naive stretch. The overlay's `GeometryReader` ignores
/// the safe area so its space is the full, edge-to-edge screen — matching the
/// preview exactly. App chrome (controls) stays inside the safe area.
struct CameraView: View {
    @Environment(AppModel.self) private var appModel
    @State private var vm: CameraViewModel
    /// Measured panel size, fed back so the panel can be clamped on-screen.
    @State private var panelSize = CGSize(width: HologramPanelView.width, height: 168)

    init(appModel: AppModel) {
        _vm = State(initialValue: CameraViewModel(appModel: appModel))
    }

    var body: some View {
        ZStack {
            // Full-bleed camera + AR overlay. `.ignoresSafeArea()` on the reader
            // makes `geo.size` the full screen, aligning overlays with the preview.
            GeometryReader { geo in
                ZStack {
                    backdrop
                    arOverlay(in: geo.size)
                }
            }
            .ignoresSafeArea()

            // Chrome — stays inside the safe area.
            if vm.authState == .denied || vm.authState == .restricted {
                CameraPermissionView()
            }
            cameraControls
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.8) {
            withAnimation { vm.debugEnabled.toggle() }
        }
        .overlay(alignment: .top) {
            if vm.debugEnabled { CameraDebugOverlay(vm: vm).padding(.top, 64) }
        }
        .onAppear {
            CameraSelfCheck.runOnce()
            #if DEBUG
            FaceOverlayGeometry.selfCheck()
            #endif
            vm.onAppear()
        }
        .onDisappear { vm.onDisappear() }
    }

    // MARK: - Backdrop

    @ViewBuilder private var backdrop: some View {
        if let session = vm.previewSession {
            CameraPreviewView(session: session)
        } else {
            SimulatedBackdrop()
        }
    }

    // MARK: - AR overlay

    private func arOverlay(in size: CGSize) -> some View {
        let activeId = vm.activeTargetTrackId
        let bounds = visibleBounds(in: size)
        return ZStack {
            // Faces: brackets + tap-to-lock targets + compact name tags.
            ForEach(vm.observations) { obs in
                faceLayer(obs, in: size, bounds: bounds, activeId: activeId)
            }

            // Center reticle ("this is the target zone").
            TargetReticleView(active: vm.isPanelVisible)
                .position(x: size.width / 2, y: size.height / 2)

            // Per-track debug tags.
            if vm.debugEnabled {
                ForEach(vm.observations) { obs in
                    let frame = FaceOverlayGeometry.displayRect(
                        normalizedTopLeft: obs.rect, imageAspect: vm.previewImageAspect, in: size)
                    if let r = vm.result(for: obs.trackId) {
                        DebugTrackTag(trackId: obs.trackId, result: r)
                            .position(x: frame.midX, y: max(frame.minY - 10, 12))
                    }
                }
            }

            // Hologram identity panel, anchored to the active face.
            if vm.isPanelVisible {
                hologramLayer(in: size, bounds: bounds)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: vm.isPanelVisible)
    }

    /// The on-screen band overlays must stay within: inset from the top bar, and
    /// from the bottom control strip plus this view's own Scan/Flip cluster.
    private func visibleBounds(in size: CGSize) -> CGRect {
        let insets = windowSafeAreaInsets()
        let topInset = insets.top + 54
        // Clear RootView's bottom control strip AND this view's Flip/Scan cluster,
        // which reaches ~264pt above the true bottom edge.
        let bottomInset = max(insets.bottom + 184, 268)
        return CGRect(
            x: 12, y: topInset,
            width: size.width - 24,
            height: max(120, size.height - topInset - bottomInset)
        )
    }

    /// Brackets + invisible tap target + (for matched non-target faces) a small name tag.
    private func faceLayer(_ obs: FaceObservation, in size: CGSize, bounds: CGRect, activeId: String?) -> some View {
        let frame = FaceOverlayGeometry.displayRect(
            normalizedTopLeft: obs.rect, imageAspect: vm.previewImageAspect, in: size)
        let isActive = obs.trackId == activeId
        let matched = vm.matchedPerson(for: obs.trackId)

        return ZStack {
            FaceBracketView(frame: frame, isActive: isActive)

            // Tap anywhere on the face to lock/unlock it as the target.
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .position(x: frame.midX, y: frame.midY)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        vm.toggleTargetLock(obs.trackId)
                    }
                }

            // Recognized roster faces get a quiet name tag (tap → profile sheet).
            // Clamp into the same visible band the panel uses so it never hides
            // behind the bottom control strip.
            if let person = matched, !isActive {
                FaceNameTag(name: person.name) { appModel.selectPerson(person.id) }
                    .position(x: clampedX(frame.midX, in: size),
                              y: min(frame.maxY + 16, bounds.maxY))
            }
        }
    }

    /// The anchored hologram panel + its connector back to the face.
    private func hologramLayer(in size: CGSize, bounds: CGRect) -> some View {
        let displayModel = vm.scanResult.map { ARIdentityDisplayModel(result: $0) }
        let accent = displayModel?.accent ?? ARTheme.scan
        let mode: HologramPanelView.Mode
        if let displayModel {
            mode = .result(displayModel)
        } else {
            mode = .scanning(vm.scanStage ?? .locked, failedStage: nil)
        }

        // Anchor rect: the active face, or a stable fallback near top-center if it
        // has briefly left the frame (so a result panel doesn't vanish).
        let faceRect: CGRect = {
            if let obs = vm.activeTargetObservation {
                return FaceOverlayGeometry.displayRect(
                    normalizedTopLeft: obs.rect, imageAspect: vm.previewImageAspect, in: size)
            }
            let w = size.width * 0.34, h = w * 1.25
            return CGRect(x: (size.width - w) / 2, y: size.height * 0.26, width: w, height: h)
        }()

        let layout = FaceOverlayGeometry.placePanel(
            faceRect: faceRect,
            panelSize: CGSize(width: HologramPanelView.width, height: panelSize.height),
            bounds: bounds
        )

        // Panel, connector and anchor dot all derive from the same `layout` and the
        // whole assembly springs in lockstep on `layout` changes — the connector
        // (an animatable Shape) interpolates with the panel, so it never detaches.
        return ZStack {
            ConnectorLine(from: layout.connectorStart, to: layout.anchorOnFace)
                .stroke(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
                .shadow(color: accent.opacity(0.4), radius: 2)
                .allowsHitTesting(false)
            AnchorDot(at: layout.anchorOnFace, accent: accent)

            HologramPanelView(
                mode: mode,
                onClose: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.dismissARPanel() } },
                onRetry: { vm.retryScan() },
                onDetails: { appModel.showIdentityDetail = true }
            )
            .background(panelSizeReader)
            // Absorb stray taps so they don't fall through and lock the face behind.
            .onTapGesture { }
            .position(x: layout.frame.midX, y: layout.frame.midY)
            .transition(.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: layout)
    }

    /// Measures the panel's real size (its height varies by state) for clamping.
    private var panelSizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { panelSize = proxy.size }
                .onChange(of: proxy.size) { _, newValue in panelSize = newValue }
        }
    }

    // MARK: - Controls

    private var cameraControls: some View {
        VStack(spacing: 14) {
            Spacer()
            if !vm.usingSimulatedSource {
                GlassCircleButton(system: "arrow.triangle.2.circlepath.camera", label: "Flip") {
                    vm.flipCamera()
                }
            }
            ScanButton(active: vm.isPanelVisible) { vm.startIdentityScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, 132)   // sit above the control strip Person D draws
    }

    // MARK: - Helpers

    private func clampedX(_ x: CGFloat, in size: CGSize) -> CGFloat {
        FaceOverlayGeometry.clamp(x, lower: 64, upper: max(64, size.width - 64))
    }

    /// Safe-area insets read from the key window (the camera ignores safe area,
    /// so geometry inside it reports zero — read the device insets directly).
    private func windowSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets
            ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }
}

// MARK: - Connector + anchor

/// A thin dashed line from the panel edge to the face bracket. An animatable
/// `Shape` so its endpoints interpolate in lockstep with the spring-animated
/// panel (otherwise the line detaches from the panel edge while a face moves).
private struct ConnectorLine: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        return p
    }
}

/// A small dot pinned to the face, showing the panel "belongs" to that person.
private struct AnchorDot: View {
    let at: CGPoint
    var accent: Color
    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: accent.opacity(0.6), radius: 3)
            .position(at)
            .allowsHitTesting(false)
    }
}

// MARK: - Buttons

/// Primary scan action: cyan, prominent, one-handed reachable.
private struct ScanButton: View {
    var active: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: active ? "rays" : "viewfinder")
                    .font(.title2.weight(.semibold))
                Text("Scan").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.black)
            .frame(width: 64, height: 64)
            .background(ARTheme.scan, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: ARTheme.scan.opacity(0.5), radius: 10, y: 3)
        }
        .accessibilityLabel("Scan the target for identity")
    }
}

/// Secondary glass circular button (camera flip).
private struct GlassCircleButton: View {
    let system: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.title3.weight(.semibold))
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(ARTheme.textPrimary)
            .frame(width: 54, height: 54)
            .hologramSurface(corner: 16, glow: false)
        }
        .accessibilityLabel(label)
    }
}

/// Compact name tag for a recognized (matched) non-target face.
private struct FaceNameTag: View {
    let name: String
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ARTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .hologramSurface(corner: 8, glow: false)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Backdrops / states (unchanged behavior, kept for the no-device path)

/// Faux camera feed for the Simulator / no-device path.
private struct SimulatedBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16),
                         Color(red: 0.03, green: 0.04, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 44
                    var x: CGFloat = 0
                    while x < geo.size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y < geo.size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
            VStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(ARTheme.textTertiary)
                Text("Simulated camera")
                    .font(.subheadline).foregroundStyle(ARTheme.textSecondary)
                Text("No device camera — running the simulated face source.")
                    .font(.caption2).foregroundStyle(ARTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: -80)
        }
    }
}

/// Shown when camera permission is unavailable.
private struct CameraPermissionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 40)).foregroundStyle(ARTheme.textSecondary)
            Text("Camera access needed")
                .font(.headline).foregroundStyle(ARTheme.textPrimary)
            Text("Enable camera access in Settings to recognize people.")
                .font(.caption).foregroundStyle(ARTheme.textSecondary)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .hologramSurface(corner: 12)
            }
        }
        .padding(28)
        .hologramSurface(corner: 20)
        .padding(40)
    }
}

/// Tiny per-track debug tag (trackId + score) drawn above the box.
private struct DebugTrackTag: View {
    let trackId: String
    let result: FaceMatchResultDTO

    var body: some View {
        Text("\(trackId) · \(result.status.rawValue)\(scoreText)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.6), in: Capsule())
    }

    private var scoreText: String {
        guard let s = result.score else { return "" }
        return String(format: " %.2f", s)
    }
}
