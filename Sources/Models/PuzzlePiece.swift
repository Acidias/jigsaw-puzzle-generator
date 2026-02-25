import AppKit
import Foundation

/// Classification of a piece based on its position in the grid.
enum PieceType: String, Codable {
    case corner
    case edge
    case interior
}

/// Represents a single jigsaw puzzle piece.
struct PuzzlePiece: Identifiable, Equatable {
    let id: UUID
    /// Sequential numeric piece identifier (row * cols + col).
    let pieceIndex: Int
    /// Bounding box top-left Y in pixels (used as approximate grid row).
    let row: Int
    /// Bounding box top-left X in pixels (used as approximate grid column).
    let col: Int
    /// Bounding box in the original image (pixels).
    let x1: Int, y1: Int, x2: Int, y2: Int
    /// Piece image dimensions (pixels).
    let pieceWidth: Int
    let pieceHeight: Int
    /// Corner, edge, or interior.
    let pieceType: PieceType
    /// Adjacent piece IDs (up, down, left, right neighbours).
    let neighbourIDs: [Int]
    /// Path to the piece image file on disk (lazy loading).
    let imagePath: URL?

    /// The extracted piece image, loaded lazily from disk on first access.
    var image: NSImage? {
        guard let imagePath else { return nil }
        return NSImage(contentsOf: imagePath)
    }

    /// Human-readable label for display in the sidebar.
    var displayLabel: String {
        let typeLabel: String
        switch pieceType {
        case .corner: typeLabel = "Corner"
        case .edge: typeLabel = "Edge"
        case .interior: typeLabel = "Interior"
        }
        return "Piece \(pieceIndex) - \(typeLabel)"
    }

    static func == (lhs: PuzzlePiece, rhs: PuzzlePiece) -> Bool {
        lhs.id == rhs.id
    }
}
