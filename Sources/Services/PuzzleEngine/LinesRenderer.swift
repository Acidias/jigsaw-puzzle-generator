import AppKit
import CoreGraphics

/// Renders all jigsaw cut lines into a single overlay image.
/// The result has black lines on a white background, designed to be composited
/// with .multiply blend mode (white becomes transparent, black lines show through).
enum LinesRenderer {

    /// Render all grid edge paths as black lines on white background.
    static func render(
        imageWidth: Int,
        imageHeight: Int,
        gridEdges: GridEdges,
        rows: Int,
        cols: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> NSImage? {
        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Flip to top-left origin (matching image pixel coordinates)
        context.translateBy(x: 0, y: CGFloat(imageHeight))
        context.scaleBy(x: 1, y: -1)

        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        // Black stroke for cut lines
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(1.0)

        // Draw horizontal edges (row boundaries)
        for r in 0..<gridEdges.horizontalEdges.count {
            for c in 0..<gridEdges.horizontalEdges[r].count {
                let edge = gridEdges.horizontalEdges[r][c]
                let startX = CGFloat(c) * cellWidth
                let startY = CGFloat(r + 1) * cellHeight
                strokeEdge(in: context, edge: edge, from: CGPoint(x: startX, y: startY))
            }
        }

        // Draw vertical edges (column boundaries)
        for r in 0..<gridEdges.verticalEdges.count {
            for c in 0..<gridEdges.verticalEdges[r].count {
                let edge = gridEdges.verticalEdges[r][c]
                let startX = CGFloat(c + 1) * cellWidth
                let startY = CGFloat(r) * cellHeight
                strokeEdge(in: context, edge: edge, from: CGPoint(x: startX, y: startY))
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: imageWidth, height: imageHeight))
    }

    /// Stroke a single edge path in the context.
    private static func strokeEdge(
        in context: CGContext,
        edge: EdgePath,
        from start: CGPoint
    ) {
        context.beginPath()
        context.move(to: start)

        var cursor = start
        for seg in edge.segments {
            let cp1 = CGPoint(x: cursor.x + seg.control1.x, y: cursor.y + seg.control1.y)
            let cp2 = CGPoint(x: cursor.x + seg.control2.x, y: cursor.y + seg.control2.y)
            let end = CGPoint(x: cursor.x + seg.end.x, y: cursor.y + seg.end.y)
            context.addCurve(to: end, control1: cp1, control2: cp2)
            cursor = end
        }

        context.strokePath()
    }
}
