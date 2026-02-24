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
    let row: Int
    let col: Int
    let topEdge: EdgeType
    let rightEdge: EdgeType
    let bottomEdge: EdgeType
    let leftEdge: EdgeType
    /// The extracted piece image (with transparency around the jigsaw shape).
    var image: NSImage?

    var pieceType: PieceType {
        let flatCount = [topEdge, rightEdge, bottomEdge, leftEdge].filter { $0 == .flat }.count
        switch flatCount {
        case 2...: return .corner
        case 1: return .edge
        default: return .interior
        }
    }

    /// Human-readable label for display in the sidebar.
    var displayLabel: String {
        let typeLabel: String
        switch pieceType {
        case .corner: typeLabel = "Corner"
        case .edge: typeLabel = "Edge"
        case .interior: typeLabel = "Interior"
        }
        return "Piece (\(row), \(col)) - \(typeLabel)"
    }

    /// Neighbours described as edge types.
    var edgeDescription: String {
        "Top: \(topEdge.rawValue), Right: \(rightEdge.rawValue), Bottom: \(bottomEdge.rawValue), Left: \(leftEdge.rawValue)"
    }

    static func == (lhs: PuzzlePiece, rhs: PuzzlePiece) -> Bool {
        lhs.id == rhs.id
    }
}
