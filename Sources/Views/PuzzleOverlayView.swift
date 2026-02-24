import SwiftUI

/// Draws the jigsaw puzzle cut lines over the original image.
struct PuzzleOverlayView: View {
    @ObservedObject var project: PuzzleProject

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let config = project.configuration
                let cellWidth = size.width / CGFloat(config.columns)
                let cellHeight = size.height / CGFloat(config.rows)

                // Use the actual seed from generation so overlay matches pieces
                let seed = project.generatedSeed != 0 ? project.generatedSeed : (config.seed == 0 ? UInt64(42) : config.seed)
                let edgeGrid = BezierEdgeGenerator.buildEdgeGrid(
                    rows: config.rows,
                    columns: config.columns,
                    seed: seed
                )

                // Draw each piece outline
                for row in 0..<config.rows {
                    for col in 0..<config.columns {
                        let origin = CGPoint(
                            x: CGFloat(col) * cellWidth,
                            y: CGFloat(row) * cellHeight
                        )

                        let piecePath = BezierEdgeGenerator.piecePath(
                            row: row, col: col,
                            cellWidth: cellWidth, cellHeight: cellHeight,
                            tabSize: config.tabSize,
                            edgeGrid: edgeGrid,
                            origin: origin
                        )

                        context.stroke(
                            piecePath,
                            with: .color(.white.opacity(0.8)),
                            lineWidth: 1.5
                        )
                        context.stroke(
                            piecePath,
                            with: .color(.black.opacity(0.4)),
                            lineWidth: 0.5
                        )
                    }
                }
            }
        }
    }
}
