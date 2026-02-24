import Foundation

/// Configuration for puzzle generation.
struct PuzzleConfiguration: Codable, Equatable {
    /// Number of columns (1-100)
    var columns: Int = 5
    /// Number of rows (1-100)
    var rows: Int = 5

    var totalPieces: Int { rows * columns }

    /// Clamp values to valid ranges.
    mutating func validate() {
        columns = max(1, min(100, columns))
        rows = max(1, min(100, rows))
        // Need at least 2 pieces total for a puzzle
        if columns == 1 && rows == 1 {
            rows = 2
        }
    }
}
