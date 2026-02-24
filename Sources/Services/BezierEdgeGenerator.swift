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
/// The classic jigsaw tab shape has three zones:
/// 1. Flat baseline -> narrow neck
/// 2. Neck -> rounded head (wider than neck, creating the interlock)
/// 3. Head -> neck -> flat baseline
///
/// Each tab is defined by control points in a normalised coordinate system
/// (0,0)-(1,0) along the edge, then transformed to actual image coordinates.
enum BezierEdgeGenerator {

    // MARK: - Edge Grid Construction

    /// Build the full edge grid with random tab/blank assignments.
    static func buildEdgeGrid(rows: Int, columns: Int, seed: UInt64) -> EdgeGrid {
        var rng = SeededRNG(seed: seed)

        // Horizontal edges: (rows+1) rows of (columns) edges each
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

        // Vertical edges: (rows) rows of (columns+1) edges each
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
        let topEdgeType = edgeGrid.horizontal[row][col]
        addEdge(
            to: &path,
            from: topLeft, to: topRight,
            edgeType: topEdgeType,
            tabSize: tabSize,
            perpendicular: CGPoint(x: 0, y: -1),
            isFirstEdge: true
        )

        // Right edge: top to bottom
        let rightEdgeType = edgeGrid.vertical[row][col + 1]
        addEdge(
            to: &path,
            from: topRight, to: bottomRight,
            edgeType: rightEdgeType,
            tabSize: tabSize,
            perpendicular: CGPoint(x: 1, y: 0),
            isFirstEdge: false
        )

        // Bottom edge: right to left
        let bottomEdgeType = edgeGrid.horizontal[row + 1][col]
        addEdge(
            to: &path,
            from: bottomRight, to: bottomLeft,
            edgeType: bottomEdgeType,
            tabSize: tabSize,
            perpendicular: CGPoint(x: 0, y: 1),
            isFirstEdge: false
        )

        // Left edge: bottom to top
        let leftEdgeType = edgeGrid.vertical[row][col]
        addEdge(
            to: &path,
            from: bottomLeft, to: topLeft,
            edgeType: leftEdgeType,
            tabSize: tabSize,
            perpendicular: CGPoint(x: -1, y: 0),
            isFirstEdge: false
        )

        path.closeSubpath()
        return path
    }

    // MARK: - Single Edge Bezier

    /// Add a single edge to the path with a classic jigsaw tab/blank shape.
    ///
    /// The shape is built from cubic bezier curves that create:
    /// - A narrow neck (pinch) at ~35-40% and ~60-65% of the edge
    /// - A wide rounded head between the neck points, protruding outward
    ///
    /// The `perpendicular` vector indicates the "outward" direction for a tab.
    /// For blanks, the direction is inverted.
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

        // Edge direction vector
        let dx = end.x - start.x
        let dy = end.y - start.y

        // Sign: tab protrudes outward (+1), blank protrudes inward (-1)
        let sign: CGFloat = edgeType == .tab ? 1.0 : -1.0

        // Helper: point at parametric position t along the edge, with perpendicular offset
        func edgePoint(t: CGFloat, perp: CGFloat) -> CGPoint {
            let offset = perp * sign
            return CGPoint(
                x: start.x + dx * t + perpendicular.x * offset,
                y: start.y + dy * t + perpendicular.y * offset
            )
        }

        let tabHeight = CGFloat(tabSize) * sqrt(dx * dx + dy * dy)

        // --- Define the classic jigsaw tab profile ---
        //
        // Positions along edge (t = 0..1):
        //   0.00        start
        //   0.34        neck entry (where we leave the baseline)
        //   0.38        neck narrowest (slight inward pinch)
        //   0.42        head start (begins to widen)
        //   0.50        head peak (max protrusion and width)
        //   0.58        head end (symmetric to head start)
        //   0.62        neck narrowest (symmetric)
        //   0.66        neck exit (back to baseline)
        //   1.00        end
        //
        // Perpendicular offsets (p, relative to tabHeight):
        //   baseline:    0
        //   neck inset:  -0.02 * tabHeight (slight pinch inward)
        //   head:        tabHeight (full protrusion)
        //   head sides:  0.8 * tabHeight

        let neckInset = -0.02 * tabHeight  // negative = slightly inward
        let headSide = 0.85 * tabHeight
        let headPeak = tabHeight

        // 1. Straight to neck entry
        let neckEntry = edgePoint(t: 0.34, perp: 0)
        path.addLine(to: neckEntry)

        // 2. Curve from neck entry into the neck (slight inward pinch),
        //    then out to the left side of the head
        let neckNarrow1 = edgePoint(t: 0.38, perp: neckInset)
        let headLeft = edgePoint(t: 0.36, perp: headSide)
        path.addCurve(
            to: edgePoint(t: 0.40, perp: headSide),
            control1: neckNarrow1,
            control2: headLeft
        )

        // 3. Curve over the head - left side to peak
        path.addCurve(
            to: edgePoint(t: 0.50, perp: headPeak),
            control1: edgePoint(t: 0.42, perp: headPeak + 0.05 * tabHeight),
            control2: edgePoint(t: 0.46, perp: headPeak + 0.02 * tabHeight)
        )

        // 4. Curve over the head - peak to right side
        path.addCurve(
            to: edgePoint(t: 0.60, perp: headSide),
            control1: edgePoint(t: 0.54, perp: headPeak + 0.02 * tabHeight),
            control2: edgePoint(t: 0.58, perp: headPeak + 0.05 * tabHeight)
        )

        // 5. Curve from right head back through neck
        let headRight = edgePoint(t: 0.64, perp: headSide)
        let neckNarrow2 = edgePoint(t: 0.62, perp: neckInset)
        path.addCurve(
            to: edgePoint(t: 0.66, perp: 0),
            control1: headRight,
            control2: neckNarrow2
        )

        // 6. Straight to end
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
