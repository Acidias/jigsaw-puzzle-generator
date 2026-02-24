import CoreGraphics
import Foundation
import SwiftUI

/// Holds the randomly-assigned edge types for the entire puzzle grid.
struct EdgeGrid {
    /// Horizontal edges: [row][col] where row 0..rows, col 0..cols-1
    /// Row 0 = top border, Row rows = bottom border
    let horizontal: [[EdgeType]]
    /// Vertical edges: [row][col] where row 0..rows-1, col 0..cols
    /// Col 0 = left border, Col cols = right border
    let vertical: [[EdgeType]]
}

/// Generates bezier paths for jigsaw puzzle piece edges.
///
/// The classic jigsaw tab is a mushroom/keyhole shape:
///
///          ___
///         /   \      <- rounded head (wider than neck)
///        |     |
///         \   /
///          | |       <- narrow neck (creates the interlock)
///          | |
///     _____|_|_____  <- flat edge baseline
///
/// The head MUST be wider than the neck for pieces to interlock.
/// This is achieved by the bezier path sweeping outward (away from
/// the edge centre) after passing through the narrow neck channel.
enum BezierEdgeGenerator {

    // MARK: - Edge Grid Construction

    /// Build the full edge grid with random tab/blank assignments.
    static func buildEdgeGrid(rows: Int, columns: Int, seed: UInt64) -> EdgeGrid {
        var rng = SeededRNG(seed: seed)

        var horizontal: [[EdgeType]] = []
        for row in 0...rows {
            var rowEdges: [EdgeType] = []
            for _ in 0..<columns {
                if row == 0 || row == rows {
                    rowEdges.append(.flat)
                } else {
                    rowEdges.append(Bool.random(using: &rng) ? .tab : .blank)
                }
            }
            horizontal.append(rowEdges)
        }

        var vertical: [[EdgeType]] = []
        for _ in 0..<rows {
            var rowEdges: [EdgeType] = []
            for col in 0...columns {
                if col == 0 || col == columns {
                    rowEdges.append(.flat)
                } else {
                    rowEdges.append(Bool.random(using: &rng) ? .tab : .blank)
                }
            }
            vertical.append(rowEdges)
        }

        return EdgeGrid(horizontal: horizontal, vertical: vertical)
    }

    // MARK: - Piece Path

    /// Construct the full closed path for a single piece.
    static func piecePath(
        row: Int, col: Int,
        cellWidth: CGFloat, cellHeight: CGFloat,
        tabSize: Double,
        edgeGrid: EdgeGrid,
        origin: CGPoint
    ) -> Path {
        var path = Path()

        let topLeft = origin
        let topRight = CGPoint(x: origin.x + cellWidth, y: origin.y)
        let bottomRight = CGPoint(x: origin.x + cellWidth, y: origin.y + cellHeight)
        let bottomLeft = CGPoint(x: origin.x, y: origin.y + cellHeight)

        // Top edge: left to right
        addEdge(
            to: &path,
            from: topLeft, to: topRight,
            edgeType: edgeGrid.horizontal[row][col],
            tabSize: tabSize,
            perpendicular: CGPoint(x: 0, y: -1),
            isFirstEdge: true
        )

        // Right edge: top to bottom
        addEdge(
            to: &path,
            from: topRight, to: bottomRight,
            edgeType: edgeGrid.vertical[row][col + 1],
            tabSize: tabSize,
            perpendicular: CGPoint(x: 1, y: 0),
            isFirstEdge: false
        )

        // Bottom edge: right to left
        addEdge(
            to: &path,
            from: bottomRight, to: bottomLeft,
            edgeType: edgeGrid.horizontal[row + 1][col],
            tabSize: tabSize,
            perpendicular: CGPoint(x: 0, y: 1),
            isFirstEdge: false
        )

        // Left edge: bottom to top
        addEdge(
            to: &path,
            from: bottomLeft, to: topLeft,
            edgeType: edgeGrid.vertical[row][col],
            tabSize: tabSize,
            perpendicular: CGPoint(x: -1, y: 0),
            isFirstEdge: false
        )

        path.closeSubpath()
        return path
    }

    // MARK: - Classic Jigsaw Tab Shape

    /// Add a single edge with a classic interlocking jigsaw tab/blank shape.
    ///
    /// The tab profile has 6 cubic bezier segments creating this outline:
    ///
    /// 1. Neck entry: baseline -> up through narrow neck
    /// 2. Undercut left: neck sweeps OUTWARD to head left (wider than neck!)
    /// 3. Head left: curves up to the peak
    /// 4. Head right: curves down from peak
    /// 5. Undercut right: head sweeps INWARD back to neck
    /// 6. Neck exit: neck -> baseline
    ///
    /// The key feature is steps 2 and 5: the path moves away from the edge
    /// centre after the narrow neck, making the head wider than the neck.
    /// This creates the classic interlocking mushroom/keyhole shape.
    private static func addEdge(
        to path: inout Path,
        from start: CGPoint, to end: CGPoint,
        edgeType: EdgeType,
        tabSize: Double,
        perpendicular: CGPoint,
        isFirstEdge: Bool
    ) {
        if isFirstEdge {
            path.move(to: start)
        }

        if edgeType == .flat {
            path.addLine(to: end)
            return
        }

        // Edge vector
        let dx = end.x - start.x
        let dy = end.y - start.y
        let edgeLength = sqrt(dx * dx + dy * dy)

        // Tab protrudes outward (+1) for .tab, inward (-1) for .blank
        let sign: CGFloat = edgeType == .tab ? 1.0 : -1.0

        // Point at position t along the edge with perpendicular offset p (in pixels)
        func pt(_ t: CGFloat, _ p: CGFloat) -> CGPoint {
            CGPoint(
                x: start.x + dx * t + perpendicular.x * p * sign,
                y: start.y + dy * t + perpendicular.y * p * sign
            )
        }

        // Tab dimensions (all in pixels, scaled from edge length)
        let h = CGFloat(tabSize) * edgeLength  // total tab height (protrusion)

        // --- Key shape parameters ---
        //
        // Neck: narrow channel from baseline up to the head
        //   Opens at t = 0.34 and 0.66 on the baseline
        //   Narrows to t = 0.40 and 0.60 (inner neck walls)
        //
        // Head: rounded knob, WIDER than the neck
        //   Widens to t = 0.32 and 0.68 (wider than neck opening!)
        //   Peak at t = 0.50
        //
        // Heights (perpendicular to edge):
        //   Baseline = 0
        //   Mid-neck = 0.20 * h
        //   Head shoulder = 0.72 * h
        //   Head peak = h

        // --- 1. Flat to neck entry ---
        path.addLine(to: pt(0.34, 0))

        // --- 2. Neck entry: from baseline, up through narrow neck ---
        // Path goes from (0.34, 0) to (0.40, 0.20*h)
        // Slightly curves inward then upward through the neck channel
        path.addCurve(
            to: pt(0.40, 0.20 * h),
            control1: pt(0.35, 0.00),           // horizontal departure from baseline
            control2: pt(0.40, 0.06 * h)        // guides upward into neck
        )

        // --- 3. Undercut left: neck sweeps outward to head ---
        // Path goes from (0.40, 0.20*h) to (0.32, 0.72*h)
        // This is the crucial undercut: x goes from 0.40 BACK to 0.32,
        // making the head wider than the neck entrance at 0.34
        path.addCurve(
            to: pt(0.32, 0.72 * h),
            control1: pt(0.40, 0.48 * h),       // rises straight up through neck
            control2: pt(0.27, 0.60 * h)        // sweeps outward past head edge
        )

        // --- 4. Head left to peak ---
        // Path goes from (0.32, 0.72*h) to (0.50, h)
        // Smooth curve over the left portion of the rounded head
        path.addCurve(
            to: pt(0.50, h),
            control1: pt(0.33, 0.92 * h),       // curves up on left shoulder
            control2: pt(0.40, h)                // rounds toward centre at peak height
        )

        // --- 5. Head peak to right ---
        // Path goes from (0.50, h) to (0.68, 0.72*h)
        // Symmetric to step 4
        path.addCurve(
            to: pt(0.68, 0.72 * h),
            control1: pt(0.60, h),               // departs centre at peak height
            control2: pt(0.67, 0.92 * h)         // curves down on right shoulder
        )

        // --- 6. Undercut right: head sweeps inward to neck ---
        // Path goes from (0.68, 0.72*h) to (0.60, 0.20*h)
        // Mirror of step 3: x goes from 0.68 BACK to 0.60
        path.addCurve(
            to: pt(0.60, 0.20 * h),
            control1: pt(0.73, 0.60 * h),       // sweeps outward past head edge
            control2: pt(0.60, 0.48 * h)        // drops straight down through neck
        )

        // --- 7. Neck exit: neck back to baseline ---
        // Path goes from (0.60, 0.20*h) to (0.66, 0)
        // Mirror of step 2
        path.addCurve(
            to: pt(0.66, 0),
            control1: pt(0.60, 0.06 * h),       // guides downward
            control2: pt(0.65, 0.00)             // meets baseline horizontally
        )

        // --- 8. Flat to edge end ---
        path.addLine(to: end)
    }
}

// MARK: - Seeded Random Number Generator

/// A simple seeded RNG (xorshift64) for reproducible puzzle generation.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
