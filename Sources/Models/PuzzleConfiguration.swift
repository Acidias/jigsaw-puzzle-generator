import Foundation

/// Background fill mode for normalised puzzle pieces.
enum PieceFill: String, Codable, CaseIterable, Equatable {
    /// Keep transparent (default, current behaviour)
    case none
    /// Fill with black
    case black
    /// Fill with white
    case white
    /// Fill with average grey computed from source image
    case grey
}

/// Configuration for puzzle generation.
struct PuzzleConfiguration: Codable, Equatable {
    /// Number of columns (1-100)
    var columns: Int = 5
    /// Number of rows (1-100)
    var rows: Int = 5
    /// Target cell size in pixels for AI normalisation (nil = normalisation off). Range 32-1024.
    var pieceSize: Int? = nil
    /// Background fill for transparent areas when normalising.
    var pieceFill: PieceFill = .none

    var totalPieces: Int { rows * columns }

    /// Clamp values to valid ranges.
    mutating func validate() {
        columns = max(1, min(100, columns))
        rows = max(1, min(100, rows))
        // Need at least 2 pieces total for a puzzle
        if columns == 1 && rows == 1 {
            rows = 2
        }
        if let size = pieceSize {
            pieceSize = max(32, min(1024, size))
        }
    }
}
