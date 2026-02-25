import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Clips the source image with a piece's CGPath and saves transparent PNGs to disk.
enum PieceClipper {

    /// The result of clipping a single piece.
    struct ClipResult: Sendable {
        /// Bounding box of the piece in the original image (integer pixels).
        let x1: Int, y1: Int, x2: Int, y2: Int
        /// Piece image dimensions.
        let width: Int, height: Int
    }

    /// Bleed margin in pixels added around the piece bounding box.
    /// Matches pixsaw's BLEED = 2 for capturing anti-aliased edge pixels.
    private static let bleed = 2

    /// Clip the source image to the given piece path and save as a transparent PNG.
    ///
    /// - Parameters:
    ///   - sourceImage: The full source image.
    ///   - piecePath: A closed CGPath in image pixel coordinates (y=0 at top).
    ///   - outputURL: Where to write the piece PNG.
    ///   - imageWidth: Source image width in pixels.
    ///   - imageHeight: Source image height in pixels.
    /// - Returns: The piece's bounding box and dimensions.
    static func clipAndSave(
        sourceImage: CGImage,
        piecePath: CGPath,
        outputURL: URL,
        imageWidth: Int,
        imageHeight: Int
    ) throws -> ClipResult {
        // Get the path's bounding box and add bleed margin
        let rawBBox = piecePath.boundingBox
        let x1 = max(0, Int(rawBBox.minX.rounded(.down)) - bleed)
        let y1 = max(0, Int(rawBBox.minY.rounded(.down)) - bleed)
        let x2 = min(imageWidth, Int(rawBBox.maxX.rounded(.up)) + bleed)
        let y2 = min(imageHeight, Int(rawBBox.maxY.rounded(.up)) + bleed)
        let pieceWidth = x2 - x1
        let pieceHeight = y2 - y1

        guard pieceWidth > 0, pieceHeight > 0 else {
            throw ClipError.emptyPiece
        }

        // Create an RGBA context for the piece (transparent background)
        guard let context = CGContext(
            data: nil,
            width: pieceWidth,
            height: pieceHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ClipError.contextCreationFailed
        }

        // Flip to image coordinates (y=0 at top)
        context.translateBy(x: 0, y: CGFloat(pieceHeight))
        context.scaleBy(x: 1, y: -1)

        // Translate so the piece's region maps to the context origin
        context.translateBy(x: CGFloat(-x1), y: CGFloat(-y1))

        // Clip to the piece path and draw the source image
        context.addPath(piecePath)
        context.clip()
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )

        // Extract the clipped image
        guard let pieceImage = context.makeImage() else {
            throw ClipError.imageExtractionFailed
        }

        // Write as PNG
        try writePNG(pieceImage, to: outputURL)

        return ClipResult(
            x1: x1, y1: y1, x2: x2, y2: y2,
            width: pieceWidth, height: pieceHeight
        )
    }

    // MARK: - Post-processing for normalisation

    /// Create a square canvas of the given size, fill with the background colour,
    /// and centre the piece image on it.
    static func padToCanvas(pieceImage: CGImage, canvasSize: Int, fillColour: CGColor) -> CGImage? {
        guard canvasSize > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: pieceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Fill background
        context.setFillColor(fillColour)
        context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        // Centre the piece on the canvas
        let x = (canvasSize - pieceImage.width) / 2
        let y = (canvasSize - pieceImage.height) / 2
        context.draw(
            pieceImage,
            in: CGRect(x: x, y: y, width: pieceImage.width, height: pieceImage.height)
        )

        return context.makeImage()
    }

    /// Compute the average grey value from a source image.
    /// Returns a CGColor in device grey colour space.
    static func averageColour(of image: CGImage) -> CGColor {
        let width = image.width
        let height = image.height
        let totalPixels = width * height
        guard totalPixels > 0 else {
            return CGColor(gray: 0.5, alpha: 1.0)
        }

        // Sample at reduced resolution for large images (max ~256x256)
        let sampleWidth: Int
        let sampleHeight: Int
        if totalPixels > 65536 {
            let scale = sqrt(65536.0 / Double(totalPixels))
            sampleWidth = max(1, Int(Double(width) * scale))
            sampleHeight = max(1, Int(Double(height) * scale))
        } else {
            sampleWidth = width
            sampleHeight = height
        }

        guard let context = CGContext(
            data: nil,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CGColor(gray: 0.5, alpha: 1.0)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        guard let data = context.data else {
            return CGColor(gray: 0.5, alpha: 1.0)
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: sampleWidth * sampleHeight * 4)
        var totalR: UInt64 = 0
        var totalG: UInt64 = 0
        var totalB: UInt64 = 0
        let count = sampleWidth * sampleHeight

        for i in 0..<count {
            let offset = i * 4
            totalR += UInt64(pixels[offset])
            totalG += UInt64(pixels[offset + 1])
            totalB += UInt64(pixels[offset + 2])
        }

        let avgR = CGFloat(totalR) / CGFloat(count) / 255.0
        let avgG = CGFloat(totalG) / CGFloat(count) / 255.0
        let avgB = CGFloat(totalB) / CGFloat(count) / 255.0
        let grey = 0.299 * avgR + 0.587 * avgG + 0.114 * avgB

        return CGColor(gray: grey, alpha: 1.0)
    }

    /// Write a CGImage as PNG to the given URL (public for post-processing overwrite).
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ClipError.pngWriteFailed(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ClipError.pngWriteFailed(url.lastPathComponent)
        }
    }

    enum ClipError: Error, LocalizedError {
        case emptyPiece
        case contextCreationFailed
        case imageExtractionFailed
        case pngWriteFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyPiece:
                return "Piece has zero dimensions."
            case .contextCreationFailed:
                return "Failed to create graphics context for piece clipping."
            case .imageExtractionFailed:
                return "Failed to extract clipped piece image."
            case .pngWriteFailed(let name):
                return "Failed to write PNG: \(name)"
            }
        }
    }
}
