import CoreGraphics
import Foundation
import SwiftUI

/// Holds the randomly-assigned edge types for the entire puzzle grid.
struct EdgeGrid {
    /// Horizontal edges: [row][col] where row 0..rows, col 0..cols-1
    let horizontal: [[EdgeType]]
    /// Vertical edges: [row][col] where row 0..rows-1, col 0..cols
    let vertical: [[EdgeType]]
}

/// Generates bezier paths for jigsaw puzzle piece edges.
///
/// Each tab is a mushroom/keyhole shape with 4 tangent-continuous cubic bezier
/// curves. All dimensions scale proportionally with the tab height (h), so the
/// shape remains consistent across different tabSize values.
///
/// Cross-section of one tab (looking at it from the side):
///
///            _____
///          /       \          <- smooth circular head
///         |         |
///          \       /
///           |     |           <- narrow neck (undercut!)
///           |     |
///     ______|     |______     <- flat edge baseline
///
/// The head (width = 0.80h) is much wider than the neck (width = 0.40h),
/// creating the classic interlocking jigsaw shape.
enum BezierEdgeGenerator {

    // MARK: - Edge Grid Construction

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

        addEdge(to: &path, from: topLeft, to: topRight,
                edgeType: edgeGrid.horizontal[row][col],
                tabSize: tabSize, perpendicular: CGPoint(x: 0, y: -1), isFirstEdge: true)

        addEdge(to: &path, from: topRight, to: bottomRight,
                edgeType: edgeGrid.vertical[row][col + 1],
                tabSize: tabSize, perpendicular: CGPoint(x: 1, y: 0), isFirstEdge: false)

        addEdge(to: &path, from: bottomRight, to: bottomLeft,
                edgeType: edgeGrid.horizontal[row + 1][col],
                tabSize: tabSize, perpendicular: CGPoint(x: 0, y: 1), isFirstEdge: false)

        addEdge(to: &path, from: bottomLeft, to: topLeft,
                edgeType: edgeGrid.vertical[row][col],
                tabSize: tabSize, perpendicular: CGPoint(x: -1, y: 0), isFirstEdge: false)

        path.closeSubpath()
        return path
    }

    // MARK: - Classic Jigsaw Tab

    /// Draws one edge with a classic jigsaw tab or blank shape.
    ///
    /// The shape uses 4 cubic bezier curves with tangent continuity at every
    /// junction, producing smooth, organic curves like a real die-cut jigsaw.
    ///
    /// All dimensions are proportional to `h` (tab height), so the shape
    /// scales uniformly and stays circular/round at any tabSize value.
    ///
    /// Shape proportions (relative to h):
    /// - Neck half-width along edge: 0.20h
    /// - Head half-width along edge: 0.40h (2x wider than neck = strong interlock)
    /// - Neck rises to: 0.30h
    /// - Head widest at: 0.72h
    /// - Head peak at: h
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

        let dx = end.x - start.x
        let dy = end.y - start.y
        let edgeLen = sqrt(dx * dx + dy * dy)
        let sign: CGFloat = edgeType == .tab ? 1.0 : -1.0

        // Tab height in pixels
        let h = CGFloat(tabSize) * edgeLen

        // Point at (t fraction along edge, p pixels perpendicular)
        func pt(_ t: CGFloat, _ p: CGFloat) -> CGPoint {
            CGPoint(
                x: start.x + dx * t + perpendicular.x * p * sign,
                y: start.y + dy * t + perpendicular.y * p * sign
            )
        }

        // --- Shape dimensions (all proportional to h) ---
        //
        // Along-edge half-widths (as fractions of edge length):
        let neckDt = 0.20 * h / edgeLen    // neck half-width
        let headDt = 0.40 * h / edgeLen    // head half-width (2x neck!)
        let sweepDt = 0.52 * h / edgeLen   // sweep CP extends past head

        // Key t positions (along edge):
        let nL = 0.50 - neckDt      // left neck entrance
        let nR = 0.50 + neckDt      // right neck entrance
        let hL = 0.50 - headDt      // left head widest
        let hR = 0.50 + headDt      // right head widest
        let sL = 0.50 - sweepDt     // left sweep CP (past head)
        let sR = 0.50 + sweepDt     // right sweep CP

        // Tangent alignment at head junction points:
        // Arrival tangent at head-left: direction from (sL, 0.50h) to (hL, 0.72h)
        //   dt = sweepDt - headDt = 0.12h/edgeLen
        //   dp = 0.22h
        // We scale this by 0.6 for the departure CP of curve 2:
        let tangentDt = 0.12 * h / edgeLen * 0.6
        let tangentDp = 0.22 * h * 0.6
        // CP for rounding the head peak:
        let peakCpDt = 0.17 * h / edgeLen

        // ================================================
        // The 4 curves (tangent-continuous at all junctions)
        // ================================================

        // --- Flat to neck ---
        path.addLine(to: pt(nL, 0))

        // --- Curve 1: Left neck + undercut sweep to head-left ---
        // Goes from baseline, UP through narrow neck, then sweeps OUT to wide head.
        // The sweep CP (sL) extends past the head edge, pulling the curve outward.
        path.addCurve(
            to: pt(hL, 0.72 * h),                // head widest left
            control1: pt(nL, 0.30 * h),           // straight up through neck
            control2: pt(sL, 0.50 * h)            // sweeps far outward past head
        )

        // --- Curve 2: Head-left to peak ---
        // Smoothly rounds over the left portion of the head.
        // CP1 is tangent-aligned with curve 1's arrival direction.
        // CP2 arrives at peak horizontally (for smooth peak).
        path.addCurve(
            to: pt(0.50, h),                      // peak centre
            control1: pt(hL + tangentDt, 0.72 * h + tangentDp),  // tangent-aligned
            control2: pt(0.50 - peakCpDt, h)      // approaches peak horizontally
        )

        // --- Curve 3: Peak to head-right ---
        // Mirror of curve 2. Departs peak horizontally.
        // CP2 is tangent-aligned with curve 4's departure direction.
        path.addCurve(
            to: pt(hR, 0.72 * h),                 // head widest right
            control1: pt(0.50 + peakCpDt, h),      // departs peak horizontally
            control2: pt(hR - tangentDt, 0.72 * h + tangentDp)   // tangent-aligned
        )

        // --- Curve 4: Head-right + undercut sweep to right neck ---
        // Mirror of curve 1. Sweeps from wide head back through narrow neck.
        path.addCurve(
            to: pt(nR, 0),                        // right neck entrance (baseline)
            control1: pt(sR, 0.50 * h),           // sweeps far outward past head
            control2: pt(nR, 0.30 * h)            // straight down through neck
        )

        // --- Flat to end ---
        path.addLine(to: end)
    }
}

// MARK: - Seeded Random Number Generator

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
