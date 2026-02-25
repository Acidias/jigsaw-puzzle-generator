import CoreGraphics

/// One cubic bezier curve segment with relative coordinates.
/// Each segment goes from the current cursor position to cursor + end,
/// with control points at cursor + control1 and cursor + control2.
struct CubicBezierSegment: Sendable {
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

/// The orientation of an edge in the puzzle grid.
enum EdgeOrientation: Sendable {
    /// Left-to-right edge (row boundary). Applies (x, -y) transform.
    case horizontal
    /// Top-to-bottom edge (column boundary). Applies (y, x) transpose.
    case vertical
}

/// A single jigsaw puzzle edge composed of 4 cubic bezier segments.
/// The segments use relative coordinates with direction transforms already applied.
struct EdgePath: Sendable {
    /// Whether the nub protrudes outward (tab) or inward (blank) from
    /// the perspective of the piece above/left of this edge.
    let isOutward: Bool
    /// The four cubic bezier segments forming this edge.
    let segments: [CubicBezierSegment]
}

/// Generates jigsaw puzzle edge paths using the interlocking nubs algorithm.
/// This is a direct port of piecemaker's interlockingnubs.py bezier curve generation.
enum EdgePathGenerator {

    /// Generate a complete edge path for the given cell dimensions and orientation.
    ///
    /// For horizontal edges, pass cellWidth/cellHeight as-is.
    /// For vertical edges, the caller should pass cellHeight as width and cellWidth as height,
    /// matching piecemaker's `VerticalPath(width=piece_height, height=piece_width)`.
    ///
    /// - Parameters:
    ///   - width: The extent of the edge in its travel direction.
    ///   - height: The extent perpendicular to travel (controls nub depth).
    ///   - isOutward: Whether the nub protrudes outward.
    ///   - orientation: Horizontal or vertical edge.
    /// - Returns: An EdgePath with 4 transformed bezier segments.
    static func generateEdge(
        width: CGFloat,
        height: CGFloat,
        isOutward: Bool,
        orientation: EdgeOrientation
    ) -> EdgePath {
        // Generate raw curve points (direct port of InterlockingCurvePoints.get_curve_points)
        let raw = generateRawCurvePoints(width: width, height: height)

        // Build 4 bezier segments from the 12 raw points
        var segments = [
            CubicBezierSegment(
                control1: raw.controlStartA,
                control2: raw.controlStartB,
                end: raw.anchorLeft
            ),
            CubicBezierSegment(
                control1: raw.controlLeftA,
                control2: raw.controlLeftB,
                end: raw.anchorCenter
            ),
            CubicBezierSegment(
                control1: raw.controlCenterA,
                control2: raw.controlCenterB,
                end: raw.anchorRight
            ),
            CubicBezierSegment(
                control1: raw.controlRightA,
                control2: raw.controlRightB,
                end: raw.relativeStop
            ),
        ]

        // Apply transforms matching Python's property getter chain:
        // 1. If not outward: invert y (Python's `invert`)
        // 2. Apply orientation transform (Python's `point` method override)
        //
        // Python transform chain for each property:
        //   out=true:  point(raw)
        //   out=false: point(invert(raw))
        //
        // HorizontalPath.point: (x, -y)
        // VerticalPath.point:   (y, x)
        // invert:               (x, -y)
        //
        // Combined:
        //   Horizontal + out=true:  (x, -y)
        //   Horizontal + out=false: (x, -(-y)) = (x, y)
        //   Vertical + out=true:    (y, x)
        //   Vertical + out=false:   (-y, x)

        segments = segments.map { seg in
            CubicBezierSegment(
                control1: transformPoint(seg.control1, isOutward: isOutward, orientation: orientation),
                control2: transformPoint(seg.control2, isOutward: isOutward, orientation: orientation),
                end: transformPoint(seg.end, isOutward: isOutward, orientation: orientation)
            )
        }

        return EdgePath(isOutward: isOutward, segments: segments)
    }

    // MARK: - Private

    /// Raw curve points before direction/orientation transforms.
    private struct RawCurvePoints {
        let controlStartA: CGPoint
        let controlStartB: CGPoint
        let anchorLeft: CGPoint
        let controlLeftA: CGPoint
        let controlLeftB: CGPoint
        let anchorCenter: CGPoint
        let controlCenterA: CGPoint
        let controlCenterB: CGPoint
        let anchorRight: CGPoint
        let controlRightA: CGPoint
        let controlRightB: CGPoint
        let relativeStop: CGPoint
    }

    /// Direct port of InterlockingCurvePoints.get_curve_points(width, height).
    /// All coordinates are relative (used with SVG `c` / CGPath addCurve relative offsets).
    private static func generateRawCurvePoints(width: CGFloat, height: CGFloat) -> RawCurvePoints {
        let anchorLeft = CGPoint(
            x: width * .random(in: 0.34...0.43),
            y: height * .random(in: -0.02...0.22)
        )

        let anchorCenter = CGPoint(
            x: (width * 0.50) - anchorLeft.x,
            y: (height * .random(in: 0.24...0.34)) - anchorLeft.y
        )

        let anchorRight = CGPoint(
            x: width * .random(in: 0.57...0.66) - (anchorLeft.x + anchorCenter.x),
            y: height * .random(in: -0.02...0.22) - (anchorLeft.y + anchorCenter.y)
        )

        let relativeStop = CGPoint(
            x: width - (anchorLeft.x + anchorCenter.x + anchorRight.x),
            y: 0.0 - (anchorLeft.y + anchorCenter.y + anchorRight.y)
        )

        let controlStartA = CGPoint(
            x: width * .random(in: 0.05...0.29),
            y: 0.0
        )

        let controlStartB = CGPoint(
            x: (width * 0.07) + anchorLeft.x,
            y: height * -0.05
        )

        let controlLeftA = CGPoint(
            x: width * -0.06,
            y: .random(in: 0.21...1.01) * anchorCenter.y
        )

        let controlLeftB = CGPoint(
            x: 0.0,
            y: anchorCenter.y
        )

        let controlCenterA = CGPoint(
            x: anchorRight.x,
            y: 0.0
        )

        let controlCenterB = CGPoint(
            x: (width * 0.06) + anchorRight.x,
            y: .random(in: 0.21...1.01) * anchorRight.y
        )

        let controlRightA = CGPoint(
            x: width * -0.06,
            y: height * -0.13
        )

        let controlRightB = CGPoint(
            x: width * 0.21,
            y: height * -0.08
        )

        return RawCurvePoints(
            controlStartA: controlStartA,
            controlStartB: controlStartB,
            anchorLeft: anchorLeft,
            controlLeftA: controlLeftA,
            controlLeftB: controlLeftB,
            anchorCenter: anchorCenter,
            controlCenterA: controlCenterA,
            controlCenterB: controlCenterB,
            anchorRight: anchorRight,
            controlRightA: controlRightA,
            controlRightB: controlRightB,
            relativeStop: relativeStop
        )
    }

    /// Apply the combined invert + orientation transform to a point.
    private static func transformPoint(
        _ p: CGPoint,
        isOutward: Bool,
        orientation: EdgeOrientation
    ) -> CGPoint {
        switch orientation {
        case .horizontal:
            // Horizontal + out=true:  (x, -y)
            // Horizontal + out=false: (x, y)
            return isOutward ? CGPoint(x: p.x, y: -p.y) : CGPoint(x: p.x, y: p.y)
        case .vertical:
            // Vertical + out=true:    (y, x)
            // Vertical + out=false:   (-y, x)
            return isOutward ? CGPoint(x: p.y, y: p.x) : CGPoint(x: -p.y, y: p.x)
        }
    }
}
