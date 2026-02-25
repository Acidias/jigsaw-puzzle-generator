import CoreGraphics

/// Handles image upscaling for small source images.
/// Small images produce jagged bezier curves when clipped at low resolution,
/// so we upscale them before processing (matching piecemaker's behaviour).
enum ImageScaler {

    /// Minimum pixels on the longest side. Images below this are upscaled.
    /// Matches the Python script's MIN_LONG_SIDE = 2000.
    static let minLongSide = 2000

    /// Upscale the image if its longest side is below the minimum threshold.
    /// Uses high-quality interpolation (matching Python's Image.LANCZOS).
    /// Returns the original image unchanged if it's already large enough.
    static func upscaleIfNeeded(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest < minLongSide else { return image }

        let scale = CGFloat(minLongSide) / CGFloat(longest)
        let newWidth = Int(CGFloat(image.width) * scale)
        let newHeight = Int(CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }
}
