import CoreGraphics

/// Handles image upscaling for small source images.
/// Small images produce jagged bezier curves when clipped at low resolution,
/// so we upscale them before processing (matching piecemaker's behaviour).
enum ImageScaler {

    /// Minimum pixels on the longest side. Images below this are upscaled.
    /// Matches the Python script's MIN_LONG_SIDE = 2000.
    static let minLongSide = 2000

    /// Centre-crop the image to match a target aspect ratio (cols:rows).
    /// If the image already matches the ratio, returns it unchanged.
    static func cropToAspectRatio(_ image: CGImage, cols: Int, rows: Int) -> CGImage {
        let targetRatio = CGFloat(cols) / CGFloat(rows)
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)

        // Already correct ratio (within floating-point tolerance)
        if abs(imageRatio - targetRatio) < 0.001 { return image }

        let cropWidth: Int
        let cropHeight: Int

        if imageRatio > targetRatio {
            // Source is wider - crop sides
            cropHeight = image.height
            cropWidth = Int(CGFloat(cropHeight) * targetRatio)
        } else {
            // Source is taller - crop top/bottom
            cropWidth = image.width
            cropHeight = Int(CGFloat(cropWidth) / targetRatio)
        }

        let x = (image.width - cropWidth) / 2
        let y = (image.height - cropHeight) / 2
        let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)

        return image.cropping(to: cropRect) ?? image
    }

    /// Resize the image to exact pixel dimensions using high-quality interpolation.
    static func resize(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage {
        guard width > 0, height > 0 else { return image }
        // Already correct size
        if image.width == width && image.height == height { return image }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

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
