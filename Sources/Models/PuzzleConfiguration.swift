import Foundation

/// Configuration for puzzle generation.
struct PuzzleConfiguration: Codable, Equatable {
    /// Number of columns (3-100)
    var columns: Int = 5
    /// Number of rows (3-100)
    var rows: Int = 5
    /// How far tabs protrude relative to cell size (0.15-0.40)
    var tabSize: Double = 0.25
    /// Random seed for reproducible generation. 0 means use a random seed.
    var seed: UInt64 = 0

    var totalPieces: Int { rows * columns }

    /// Clamp values to valid ranges.
    mutating func validate() {
        columns = max(3, min(100, columns))
        rows = max(3, min(100, rows))
        tabSize = max(0.15, min(0.40, tabSize))
    }
}
