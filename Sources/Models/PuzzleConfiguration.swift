import Foundation

/// Configuration for puzzle generation.
struct PuzzleConfiguration: Codable, Equatable {
    /// Number of columns (3-100)
    var columns: Int = 5
    /// Number of rows (3-100)
    var rows: Int = 5

    var totalPieces: Int { rows * columns }

    /// Clamp values to valid ranges.
    mutating func validate() {
        columns = max(3, min(100, columns))
        rows = max(3, min(100, rows))
    }
}
