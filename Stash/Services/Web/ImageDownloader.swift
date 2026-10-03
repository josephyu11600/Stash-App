import Foundation
import ImageIO
import UIKit

nonisolated struct DownloadedImage: Sendable {
    let source: URL
    /// Downsampled to at most `maxStoredPixels`, flattened JPEG — what gets saved.
    let full: Data
    /// Small JPEG sent to the model for visual verification.
    let preview: Data
}

nonisolated enum ImageDownloader {
    private static let minPixels = 150
    private static let maxStoredPixels = 1600
    private static let previewPixels = 512

    static func download(_ url: URL) async -> DownloadedImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return await process(data, source: url)
    }

    @concurrent
    private static func process(_ data: Data, source: URL) async -> DownloadedImage? {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              min(width, height) >= minPixels,
              let full = render(image, maxPixels: maxStoredPixels),
              let preview = render(image, maxPixels: previewPixels)
        else { return nil }
        return DownloadedImage(source: source, full: full, preview: preview)
    }

    /// Decodes at reduced size (never the full bitmap) and flattens transparency onto white,
    /// so PNG product shots don't turn black as JPEG.
    private static func render(_ source: CGImageSource, maxPixels: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
