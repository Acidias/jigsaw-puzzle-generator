import CoreGraphics

/// Stores all pre-generated edge curves for the entire puzzle grid.
/// Edges are shared between adjacent pieces - one piece traverses an edge forward,
/// the neighbouring piece traverses it in reverse.
struct GridEdges: Sendable {
    /// Horizontal edges (row boundaries).
    /// horizontalEdges[r][c] is the edge between row r and row r+1, at column c.
    /// Dimensions: (rows-1) x cols.
    let horizontalEdges: [[EdgePath]]

    /// Vertical edges (column boundaries).
    /// verticalEdges[r][c] is the edge between column c and column c+1, at row r.
    /// Dimensions: rows x (cols-1).
    let verticalEdges: [[EdgePath]]

    /// Generate all edges for a grid with random tab directions.
    static func generate(
        rows: Int,
        cols: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> GridEdges {
        // Horizontal edges: (rows-1) boundaries, each with cols edge segments
        var hEdges: [[EdgePath]] = []
        for _ in 0..<(rows - 1) {
            var row: [EdgePath] = []
            for _ in 0..<cols {
                let isOutward = Bool.random()
                let edge = EdgePathGenerator.generateEdge(
                    width: cellWidth,
                    height: cellHeight,
                    isOutward: isOutward,
                    orientation: .horizontal
                )
                row.append(edge)
            }
            hEdges.append(row)
        }

        // Vertical edges: rows boundaries, each with (cols-1) edge segments
        // Note: piecemaker uses VerticalPath(width=piece_height, height=piece_width)
        // so we swap the parameters here
        var vEdges: [[EdgePath]] = []
        for _ in 0..<rows {
            var row: [EdgePath] = []
            for _ in 0..<(cols - 1) {
                let isOutward = Bool.random()
                let edge = EdgePathGenerator.generateEdge(
                    width: cellHeight,
                    height: cellWidth,
                    isOutward: isOutward,
                    orientation: .vertical
                )
                row.append(edge)
            }
            vEdges.append(row)
        }

        return GridEdges(horizontalEdges: hEdges, verticalEdges: vEdges)
    }
}

/// Builds closed CGPath outlines for individual puzzle pieces.
enum PiecePathBuilder {

    /// Build a closed CGPath for the piece at grid position (row, col).
    /// The path uses absolute image pixel coordinates.
    static func buildPiecePath(
        row: Int,
        col: Int,
        rows: Int,
        cols: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        gridEdges: GridEdges
    ) -> CGPath {
        let path = CGMutablePath()
        let originX = CGFloat(col) * cellWidth
        let originY = CGFloat(row) * cellHeight

        // Start at top-left corner of this piece
        path.move(to: CGPoint(x: originX, y: originY))

        // TOP EDGE (left to right)
        if row == 0 {
            // Border - straight line
            path.addLine(to: CGPoint(x: originX + cellWidth, y: originY))
        } else {
            // Follow horizontalEdges[row-1][col] forward
            let edge = gridEdges.horizontalEdges[row - 1][col]
            addEdgeForward(to: path, edge: edge, from: CGPoint(x: originX, y: originY))
        }

        // RIGHT EDGE (top to bottom)
        if col == cols - 1 {
            // Border - straight line
            path.addLine(to: CGPoint(x: originX + cellWidth, y: originY + cellHeight))
        } else {
            // Follow verticalEdges[row][col] forward
            let edge = gridEdges.verticalEdges[row][col]
            addEdgeForward(
                to: path,
                edge: edge,
                from: CGPoint(x: originX + cellWidth, y: originY)
            )
        }

        // BOTTOM EDGE (right to left - REVERSED)
        if row == rows - 1 {
            // Border - straight line
            path.addLine(to: CGPoint(x: originX, y: originY + cellHeight))
        } else {
            // Follow horizontalEdges[row][col] in reverse
            let edge = gridEdges.horizontalEdges[row][col]
            addEdgeReversed(
                to: path,
                edge: edge,
                from: CGPoint(x: originX + cellWidth, y: originY + cellHeight)
            )
        }

        // LEFT EDGE (bottom to top - REVERSED)
        if col == 0 {
            // Border - straight line
            path.addLine(to: CGPoint(x: originX, y: originY))
        } else {
            // Follow verticalEdges[row][col-1] in reverse
            let edge = gridEdges.verticalEdges[row][col - 1]
            addEdgeReversed(
                to: path,
                edge: edge,
                from: CGPoint(x: originX, y: originY + cellHeight)
            )
        }

        path.closeSubpath()
        return path
    }

    // MARK: - Edge Traversal

    /// Add an edge's bezier segments in forward direction.
    /// Converts relative segment offsets to absolute CGPath curves.
    private static func addEdgeForward(
        to path: CGMutablePath,
        edge: EdgePath,
        from start: CGPoint
    ) {
        var cursor = start
        for seg in edge.segments {
            let cp1 = CGPoint(x: cursor.x + seg.control1.x, y: cursor.y + seg.control1.y)
            let cp2 = CGPoint(x: cursor.x + seg.control2.x, y: cursor.y + seg.control2.y)
            let end = CGPoint(x: cursor.x + seg.end.x, y: cursor.y + seg.end.y)
            path.addCurve(to: end, control1: cp1, control2: cp2)
            cursor = end
        }
    }

    /// Add an edge's bezier segments in reverse direction.
    ///
    /// Reversing a cubic bezier from A to A+end with controls at A+cp1 and A+cp2:
    /// - New start is the old end (A+end)
    /// - Traverse segments in reverse order
    /// - For each segment, the reversed relative offsets are:
    ///   new_cp1 = cp2 - end, new_cp2 = cp1 - end, new_end = -end
    private static func addEdgeReversed(
        to path: CGMutablePath,
        edge: EdgePath,
        from start: CGPoint
    ) {
        var cursor = start
        for seg in edge.segments.reversed() {
            let cp1 = CGPoint(
                x: cursor.x + seg.control2.x - seg.end.x,
                y: cursor.y + seg.control2.y - seg.end.y
            )
            let cp2 = CGPoint(
                x: cursor.x + seg.control1.x - seg.end.x,
                y: cursor.y + seg.control1.y - seg.end.y
            )
            let end = CGPoint(
                x: cursor.x - seg.end.x,
                y: cursor.y - seg.end.y
            )
            path.addCurve(to: end, control1: cp1, control2: cp2)
            cursor = end
        }
    }
}
