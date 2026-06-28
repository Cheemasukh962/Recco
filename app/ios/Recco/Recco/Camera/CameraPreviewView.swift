import SwiftUI
import AVFoundation

/// SwiftUI wrapper over `AVCaptureVideoPreviewLayer`. Fills the screen with the
/// live feed (`.resizeAspectFill`), matching the normalized-rect math in
/// `FaceGeometry` used to place overlays.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        Self.applyPortraitRotation(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        Self.applyPortraitRotation(uiView.previewLayer)
    }

    /// Pin the preview connection to the same 90° upright-portrait rotation the
    /// `CameraSession` applies to its video-data output. This guarantees the
    /// displayed image shares the exact coordinate space the Vision boxes are
    /// normalized in — which is what makes `FaceOverlayGeometry.displayRect`'s
    /// aspect-fill mapping line the AR brackets up with real faces.
    private static func applyPortraitRotation(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }

    /// Backing view whose layer *is* the preview layer.
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
