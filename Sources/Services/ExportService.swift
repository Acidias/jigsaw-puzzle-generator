import AppKit
import Foundation

/// Exports puzzle pieces as individual PNG files with a metadata JSON.
enum ExportService {

    @MainActor
    static func export(project: PuzzleProject, to directory: URL) async {
        let puzzleDir = directory.appendingPathComponent(project.name)
        let piecesDir = puzzleDir.appendingPathComponent("pieces")

        do {
            try FileManager.default.createDirectory(at: piecesDir, withIntermediateDirectories: true)

            // Export each piece as PNG
            for piece in project.pieces {
                guard let image = piece.image,
                      let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else { continue }

                let filename = "piece_\(piece.row)_\(piece.col).png"
                let fileURL = piecesDir.appendingPathComponent(filename)
                try pngData.write(to: fileURL)
            }

            // Generate metadata JSON
            let metadata = buildMetadata(project: project)
            let jsonData = try JSONEncoder().encode(metadata)
            let metadataURL = puzzleDir.appendingPathComponent("metadata.json")

            // Pretty-print the JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted) {
                try prettyData.write(to: metadataURL)
            } else {
                try jsonData.write(to: metadataURL)
            }

        } catch {
            print("Export failed: \(error)")
        }
    }

    @MainActor
    private static func buildMetadata(project: PuzzleProject) -> PuzzleMetadata {
        let pieces = project.pieces.map { piece in
            PieceMetadata(
                row: piece.row,
                col: piece.col,
                type: piece.pieceType.rawValue,
                topEdge: piece.topEdge.rawValue,
                rightEdge: piece.rightEdge.rawValue,
                bottomEdge: piece.bottomEdge.rawValue,
                leftEdge: piece.leftEdge.rawValue,
                filename: "piece_\(piece.row)_\(piece.col).png"
            )
        }

        return PuzzleMetadata(
            sourceName: project.name,
            sourceWidth: project.imageWidth,
            sourceHeight: project.imageHeight,
            columns: project.configuration.columns,
            rows: project.configuration.rows,
            tabSize: project.configuration.tabSize,
            seed: project.configuration.seed,
            totalPieces: project.configuration.totalPieces,
            pieces: pieces
        )
    }
}

// MARK: - Metadata Models

struct PuzzleMetadata: Codable {
    let sourceName: String
    let sourceWidth: Int
    let sourceHeight: Int
    let columns: Int
    let rows: Int
    let tabSize: Double
    let seed: UInt64
    let totalPieces: Int
    let pieces: [PieceMetadata]
}

struct PieceMetadata: Codable {
    let row: Int
    let col: Int
    let type: String
    let topEdge: String
    let rightEdge: String
    let bottomEdge: String
    let leftEdge: String
    let filename: String
}
