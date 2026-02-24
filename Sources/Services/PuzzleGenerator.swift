import AppKit
import Foundation

/// Orchestrates the full puzzle generation pipeline:
/// 1. Build edge grid (random tab/blank assignments)
/// 2. Clip each piece from the source image
/// 3. Return PuzzlePiece array with images and metadata
actor PuzzleGenerator {

    func generate(
        image: NSImage,
        configuration: PuzzleConfiguration,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> [PuzzlePiece] {
        var config = configuration
        config.validate()

        let seed = config.seed == 0 ? UInt64.random(in: 1...UInt64.max) : config.seed

        // Get the CGImage from NSImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let imageSize = CGSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )

        // Build the edge grid
        let edgeGrid = BezierEdgeGenerator.buildEdgeGrid(
            rows: config.rows,
            columns: config.columns,
            seed: seed
        )

        // Clip all pieces
        let clippedPieces = ImageClipper.clipAllPieces(
            from: cgImage,
            imageSize: imageSize,
            rows: config.rows,
            columns: config.columns,
            tabSize: config.tabSize,
            edgeGrid: edgeGrid,
            onProgress: onProgress
        )

        // Build PuzzlePiece models
        var pieces: [PuzzlePiece] = []
        for item in clippedPieces {
            let row = item.row
            let col = item.col

            let piece = PuzzlePiece(
                id: UUID(),
                row: row,
                col: col,
                topEdge: edgeGrid.horizontal[row][col],
                rightEdge: edgeGrid.vertical[row][col + 1],
                bottomEdge: edgeGrid.horizontal[row + 1][col],
                leftEdge: edgeGrid.vertical[row][col],
                image: item.image
            )
            pieces.append(piece)
        }

        return pieces
    }
}
