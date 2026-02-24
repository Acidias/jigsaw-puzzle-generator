import AppKit
import CoreGraphics
import Foundation

/// Clips an image region to a bezier path shape, producing a piece image with transparency.
enum ImageClipper {

    /// Extract a single puzzle piece from the source image.
    ///
    /// The paths from BezierEdgeGenerator use top-down coordinates (y increases downward),
    /// matching typical image coordinates. Core Graphics uses bottom-up coordinates
    /// (y increases upward). We transform the path to CG coordinates before clipping.
    static func clipPiece(
        from source: CGImage,
        piecePath: CGPath,
        imageSize: CGSize
    ) -> NSImage? {
        // Transform the path from top-down to CG bottom-up coordinates
        var flipTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: imageSize.height)
        guard let cgPath = piecePath.copy(using: &flipTransform) else { return nil }

        // Get bounds in CG coordinate space with small padding for anti-aliasing
        let rawBounds = cgPath.boundingBox
        let bounds = rawBounds.insetBy(dx: -2, dy: -2)

        // Clamp to image area
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clampedBounds = bounds.intersection(imageBounds)
        guard !clampedBounds.isEmpty else { return nil }

        let width = Int(ceil(clampedBounds.width))
        let height = Int(ceil(clampedBounds.height))
        guard width > 0, height > 0 else { return nil }

        // Create bitmap context with alpha channel for transparency
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Enable anti-aliasing for smooth edges
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Translate so the bounding box origin maps to context (0,0)
        context.translateBy(x: -clampedBounds.origin.x, y: -clampedBounds.origin.y)

        // Clip to piece shape
        context.addPath(cgPath)
        context.clip()

        // Draw the source image. In CG coordinates, origin (0,0) is bottom-left.
        context.draw(source, in: CGRect(origin: .zero, size: imageSize))

        guard let resultCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: resultCGImage, size: NSSize(width: width, height: height))
    }

    /// Extract all pieces from the source image.
    static func clipAllPieces(
        from source: CGImage,
        imageSize: CGSize,
        rows: Int,
        columns: Int,
        tabSize: Double,
        edgeGrid: EdgeGrid,
        onProgress: @Sendable (Double) -> Void
    ) -> [(row: Int, col: Int, image: NSImage)] {
        let cellWidth = imageSize.width / CGFloat(columns)
        let cellHeight = imageSize.height / CGFloat(rows)
        let totalPieces = rows * columns
        var results: [(row: Int, col: Int, image: NSImage)] = []

        for row in 0..<rows {
            for col in 0..<columns {
                let origin = CGPoint(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(row) * cellHeight
                )

                let swiftUIPath = BezierEdgeGenerator.piecePath(
                    row: row, col: col,
                    cellWidth: cellWidth, cellHeight: cellHeight,
                    tabSize: tabSize,
                    edgeGrid: edgeGrid,
                    origin: origin
                )

                let cgPath = swiftUIPath.cgPath

                if let pieceImage = clipPiece(from: source, piecePath: cgPath, imageSize: imageSize) {
                    results.append((row: row, col: col, image: pieceImage))
                }

                let completedCount = row * columns + col + 1
                let progress = Double(completedCount) / Double(totalPieces)
                onProgress(progress)
            }
        }

        return results
    }
}
