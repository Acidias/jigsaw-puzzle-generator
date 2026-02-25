import AppKit
import Foundation

/// Errors that can occur during puzzle export.
enum ExportError: Error, LocalizedError {
    case directoryCreationFailed(String)
    case pieceCopyFailed(pieceIndex: Int, reason: String)
    case pieceImageMissing(pieceIndex: Int)
    case metadataWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let reason):
            return "Failed to create export directory: \(reason)"
        case .pieceCopyFailed(let index, let reason):
            return "Failed to export piece \(index): \(reason)"
        case .pieceImageMissing(let index):
            return "Piece \(index) has no image file or the source file has been deleted."
        case .metadataWriteFailed(let reason):
            return "Failed to write metadata: \(reason)"
        }
    }
}

/// Exports puzzle pieces as individual PNG files with a metadata JSON.
enum ExportService {

    @MainActor
    static func export(image: PuzzleImage, to directory: URL) throws {
        let puzzleDir = directory.appendingPathComponent(image.name)
        let piecesDir = puzzleDir.appendingPathComponent("pieces")

        do {
            try FileManager.default.createDirectory(at: piecesDir, withIntermediateDirectories: true)
        } catch {
            throw ExportError.directoryCreationFailed(error.localizedDescription)
        }

        // Export each piece as PNG - copy from disk when possible
        for piece in image.pieces {
            let filename = "piece_\(piece.pieceIndex).png"
            let destURL = piecesDir.appendingPathComponent(filename)

            if let sourcePath = piece.imagePath,
               FileManager.default.fileExists(atPath: sourcePath.path) {
                // Fast path: copy the existing PNG file directly
                do {
                    try FileManager.default.copyItem(at: sourcePath, to: destURL)
                } catch {
                    throw ExportError.pieceCopyFailed(pieceIndex: piece.pieceIndex, reason: error.localizedDescription)
                }
            } else if let pieceImage = piece.image,
                      let tiffData = pieceImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) {
                // Fallback: re-encode from NSImage
                do {
                    try pngData.write(to: destURL)
                } catch {
                    throw ExportError.pieceCopyFailed(pieceIndex: piece.pieceIndex, reason: error.localizedDescription)
                }
            } else {
                throw ExportError.pieceImageMissing(pieceIndex: piece.pieceIndex)
            }
        }

        // Export lines overlay if available (always re-encode since it's an NSImage).
        // Not critical - skip silently if encoding fails since pieces are the main output.
        if let linesImage = image.linesImage,
           let tiffData = linesImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let linesURL = puzzleDir.appendingPathComponent("lines.png")
            try? pngData.write(to: linesURL)
        }

        // Generate metadata JSON
        let metadata = buildMetadata(image: image)
        do {
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
            throw ExportError.metadataWriteFailed(error.localizedDescription)
        }
    }

    @MainActor
    private static func buildMetadata(image: PuzzleImage) -> PuzzleMetadata {
        let pieces = image.pieces.map { piece in
            PieceMetadata(
                id: piece.pieceIndex,
                type: piece.pieceType.rawValue,
                x1: piece.x1, y1: piece.y1,
                x2: piece.x2, y2: piece.y2,
                width: piece.pieceWidth,
                height: piece.pieceHeight,
                neighbours: piece.neighbourIDs,
                filename: "piece_\(piece.pieceIndex).png"
            )
        }

        return PuzzleMetadata(
            sourceName: image.name,
            sourceWidth: image.imageWidth,
            sourceHeight: image.imageHeight,
            requestedPieces: image.configuration.totalPieces,
            actualPieces: image.pieces.count,
            pieces: pieces,
            attribution: image.attribution
        )
    }
}

// MARK: - Metadata Models

struct PuzzleMetadata: Codable {
    let sourceName: String
    let sourceWidth: Int
    let sourceHeight: Int
    let requestedPieces: Int
    let actualPieces: Int
    let pieces: [PieceMetadata]
    let attribution: ImageAttribution?
}

struct PieceMetadata: Codable {
    let id: Int
    let type: String
    let x1: Int, y1: Int, x2: Int, y2: Int
    let width: Int
    let height: Int
    let neighbours: [Int]
    let filename: String
}
