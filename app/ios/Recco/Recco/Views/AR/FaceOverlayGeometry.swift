import CoreGraphics
import Foundation

/// Maps normalized face rectangles onto the live preview's view space, and places
/// the hologram panel beside a face while keeping it on-screen.
///
/// This is the piece that makes AR brackets line up with real faces. The preview
/// layer renders with `AVLayerVideoGravity.resizeAspectFill`, which **scales the
/// camera image to *cover* the view and crops the overflow** — so a naive
/// `normalized × size` mapping drifts (faces slide toward center on the
/// overflowing axis). `displayRect` reproduces the exact aspect-fill transform.
///
/// Coordinate space: `FaceObservation.rect` is already normalized **top-left**
/// (0...1) in the *oriented* (upright-portrait) image the tracker sees — see
/// `FaceGeometry.visionToNormalizedTopLeft`. `imageAspect` is that oriented
/// image's width ÷ height (≈0.5625 for a 1080×1920 portrait buffer). Pass `nil`
/// for the simulated source, whose boxes are authored directly in screen space.
///
/// Pure & dependency-free so it can be reasoned about and self-checked
/// (`FaceOverlayGeometry.selfCheck()`), matching `FaceGeometry`'s philosophy.
enum FaceOverlayGeometry {

    // MARK: - Aspect-fill mapping

    /// Convert a normalized (top-left, 0...1) rect into the on-screen rect the
    /// `.resizeAspectFill` preview actually shows it at.
    ///
    /// - When `imageAspect == nil` (or degenerate), falls back to a plain stretch
    ///   (`normalized × size`) — correct for the simulated, screen-authored boxes.
    static func displayRect(normalizedTopLeft n: CGRect,
                            imageAspect: CGFloat?,
                            in size: CGSize) -> CGRect {
        guard let imageAspect, imageAspect > 0,
              size.width > 0, size.height > 0 else {
            return CGRect(x: n.minX * size.width,
                          y: n.minY * size.height,
                          width: n.width * size.width,
                          height: n.height * size.height)
        }

        let viewAspect = size.width / size.height
        // The image is scaled to fully *cover* the view; one axis overflows.
        var scaledW = size.width
        var scaledH = size.height
        if imageAspect > viewAspect {
            // Image is relatively wider → height fills, width overflows (cropped L/R).
            scaledH = size.height
            scaledW = size.height * imageAspect
        } else {
            // Image is relatively taller → width fills, height overflows (cropped T/B).
            scaledW = size.width
            scaledH = size.width / imageAspect
        }
        let offsetX = (scaledW - size.width) / 2
        let offsetY = (scaledH - size.height) / 2

        return CGRect(
            x: n.minX * scaledW - offsetX,
            y: n.minY * scaledH - offsetY,
            width: n.width * scaledW,
            height: n.height * scaledH
        )
    }

    // MARK: - Panel placement

    enum PanelSide { case topTrailing, topLeading, below, above }

    /// Where to draw the hologram panel and how to connect it back to the face.
    struct PanelLayout: Equatable {
        var frame: CGRect          // panel rect in view space (clamped on-screen)
        var anchorOnFace: CGPoint  // point on the face bracket the connector targets
        var connectorStart: CGPoint// point on the panel edge the connector leaves from
        var side: PanelSide
    }

    /// Place a `panelSize` panel near `faceRect`, preferring the face's top-right,
    /// flipping to top-left / below / above when there is no room, and finally
    /// clamping fully inside `bounds` (the visible region inset from app chrome).
    static func placePanel(faceRect: CGRect,
                           panelSize: CGSize,
                           bounds: CGRect,
                           gap: CGFloat = 14) -> PanelLayout {
        let w = panelSize.width
        let h = panelSize.height

        // Align the panel's top a touch above the head, but never off the band.
        let topY = clamp(faceRect.minY - 6, lower: bounds.minY, upper: bounds.maxY - h)
        let rightX = faceRect.maxX + gap
        let leftX  = faceRect.minX - gap - w
        let belowY = faceRect.maxY + gap
        let centeredX = clamp(faceRect.midX - w / 2, lower: bounds.minX, upper: bounds.maxX - w)

        let side: PanelSide
        var origin: CGPoint
        if rightX + w <= bounds.maxX {
            side = .topTrailing; origin = CGPoint(x: rightX, y: topY)
        } else if leftX >= bounds.minX {
            side = .topLeading;  origin = CGPoint(x: leftX, y: topY)
        } else if belowY + h <= bounds.maxY {
            side = .below;       origin = CGPoint(x: centeredX, y: belowY)
        } else {
            side = .above
            origin = CGPoint(x: centeredX,
                             y: clamp(faceRect.minY - gap - h, lower: bounds.minY, upper: bounds.maxY - h))
        }

        // Final safety clamp (handles tiny `bounds` gracefully).
        origin.x = clamp(origin.x, lower: bounds.minX, upper: max(bounds.minX, bounds.maxX - w))
        origin.y = clamp(origin.y, lower: bounds.minY, upper: max(bounds.minY, bounds.maxY - h))
        let frame = CGRect(origin: origin, size: panelSize)

        let anchorOnFace: CGPoint
        let connectorStart: CGPoint
        switch side {
        case .topTrailing:
            anchorOnFace = CGPoint(x: faceRect.maxX, y: faceRect.minY + faceRect.height * 0.18)
            connectorStart = CGPoint(x: frame.minX,
                                     y: clamp(anchorOnFace.y, lower: frame.minY + 10, upper: frame.maxY - 10))
        case .topLeading:
            anchorOnFace = CGPoint(x: faceRect.minX, y: faceRect.minY + faceRect.height * 0.18)
            connectorStart = CGPoint(x: frame.maxX,
                                     y: clamp(anchorOnFace.y, lower: frame.minY + 10, upper: frame.maxY - 10))
        case .below:
            anchorOnFace = CGPoint(x: faceRect.midX, y: faceRect.maxY)
            connectorStart = CGPoint(x: clamp(faceRect.midX, lower: frame.minX + 12, upper: frame.maxX - 12),
                                     y: frame.minY)
        case .above:
            anchorOnFace = CGPoint(x: faceRect.midX, y: faceRect.minY)
            connectorStart = CGPoint(x: clamp(faceRect.midX, lower: frame.minX + 12, upper: frame.maxX - 12),
                                     y: frame.maxY)
        }
        return PanelLayout(frame: frame, anchorOnFace: anchorOnFace, connectorStart: connectorStart, side: side)
    }

    // MARK: - Helpers

    @inline(__always)
    static func clamp(_ v: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        upper < lower ? lower : min(max(v, lower), upper)
    }

    // MARK: - Self-check (mirrors CameraSelfCheck's runtime asserts)

    /// Lightweight invariants verified once at launch (DEBUG only). Catches a
    /// regression in the aspect-fill math without needing a device.
    static func selfCheck() {
        let size = CGSize(width: 393, height: 852)         // iPhone 15-ish points
        let aspect: CGFloat = 1080.0 / 1920.0              // portrait buffer 0.5625

        // 1. A horizontally-centered box maps to the horizontal screen center,
        //    regardless of aspect-fill cropping.
        let centeredX = CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.20)
        let mappedC = displayRect(normalizedTopLeft: centeredX, imageAspect: aspect, in: size)
        assert(abs(mappedC.midX - size.width / 2) < 0.5,
               "aspect-fill: centered box must stay horizontally centered")

        // 2. A vertically-centered box stays vertically centered when height fills.
        let centeredY = CGRect(x: 0.30, y: 0.40, width: 0.20, height: 0.20)
        let mappedCY = displayRect(normalizedTopLeft: centeredY, imageAspect: aspect, in: size)
        assert(abs(mappedCY.midY - size.height / 2) < 0.5,
               "aspect-fill: centered box must stay vertically centered")

        // 3. With aspect == view aspect there is no crop (plain stretch).
        let square = displayRect(normalizedTopLeft: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 imageAspect: size.width / size.height, in: size)
        assert(abs(square.width - size.width) < 0.5 && abs(square.height - size.height) < 0.5,
               "matching aspect must be an identity stretch")

        // 4. nil aspect → plain stretch.
        let stretched = displayRect(normalizedTopLeft: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                                    imageAspect: nil, in: size)
        assert(abs(stretched.minX - size.width * 0.5) < 0.5, "nil aspect must stretch")

        // 5. Panel placement always lands fully inside the bounds.
        let bounds = CGRect(x: 12, y: 70, width: size.width - 24, height: size.height - 270)
        for face in [CGRect(x: 20, y: 100, width: 120, height: 150),     // left edge
                     CGRect(x: 250, y: 120, width: 120, height: 150),    // right edge
                     CGRect(x: 130, y: 90, width: 150, height: 180)] {   // center/large
            let p = placePanel(faceRect: face, panelSize: CGSize(width: 232, height: 150), bounds: bounds)
            assert(bounds.insetBy(dx: -0.5, dy: -0.5).contains(p.frame),
                   "panel must stay inside the visible band")
        }
    }
}
