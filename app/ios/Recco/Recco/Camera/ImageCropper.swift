import Foundation
import CoreImage
import UIKit
import CoreGraphics
import CoreVideo

/// Generic image cropper for an arbitrary normalized (top-left, 0...1) rect.
///
/// `FaceCropper` is tuned for tight face crops (fixed padding + upscaling toward
/// 160px + a 96px floor). The identity lane also needs a *wider* "context" crop
/// that includes the chest / lanyard / name-tag area, at an arbitrary rect and
/// caller-chosen JPEG quality — that is what this helper provides. It mirrors
/// FaceCropper's CoreImage bottom-left y-flip so the crop is not vertically
/// mirrored.
final class ImageCropper {

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    enum CropError: Error { case tooSmall, encodeFailed }

    /// Minimum pixel edge accepted (skip degenerate crops).
    private let minEdge: CGFloat = 64

    /// Crop `normalizedRect` (top-left, 0...1) out of `pixelBuffer` and return a
    /// base64 JPEG at `jpegQuality`. The rect is clamped to the unit square.
    /// Upscales smaller crops so badge/name-tag text is still readable by OCR.
    func base64JPEG(from pixelBuffer: CVPixelBuffer,
                    normalizedRect: CGRect,
                    jpegQuality: CGFloat = 0.85,
                    targetMinEdge: CGFloat = 900,
                    maxOutputEdge: CGFloat = 1600) throws -> String {
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Clamp to the unit square, then map to pixels (top-left origin).
        let clamped = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else {
            throw CropError.tooSmall
        }
        let cropRect = CGRect(
            x: clamped.origin.x * imageWidth,
            y: clamped.origin.y * imageHeight,
            width: clamped.width * imageWidth,
            height: clamped.height * imageHeight
        )
        guard cropRect.width >= minEdge, cropRect.height >= minEdge else {
            throw CropError.tooSmall
        }

        // CoreImage uses a bottom-left origin; flip the top-left crop rect.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let flippedY = imageHeight - cropRect.origin.y - cropRect.height
        let ciCrop = CGRect(x: cropRect.origin.x, y: flippedY,
                            width: cropRect.width, height: cropRect.height)
        let cropped = ciImage.cropped(to: ciCrop)
        let shortest = min(cropRect.width, cropRect.height)
        let longest = max(cropRect.width, cropRect.height)
        var scale = max(1.0, targetMinEdge / max(shortest, 1))
        if longest * scale > maxOutputEdge {
            scale = max(1.0, maxOutputEdge / max(longest, 1))
        }
        let output = scale > 1
            ? cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : cropped

        guard let cg = context.createCGImage(output, from: output.extent) else {
            throw CropError.encodeFailed
        }
        guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: jpegQuality) else {
            throw CropError.encodeFailed
        }
        return data.base64EncodedString()
    }
}
