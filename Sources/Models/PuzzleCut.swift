import AppKit
import Combine
import Foundation

/// One puzzle generation result for an image - a specific grid size and its pieces.
/// An image can have multiple cuts at different grid sizes (e.g. 3x3, 5x5, 10x10).
@MainActor
class PuzzleCut: ObservableObject, Identifiable {
    let id: UUID
    @Published var configuration: PuzzleConfiguration
    @Published var pieces: [PuzzlePiece] = []
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    /// The puzzle cut lines overlay image.
    @Published var linesImage: NSImage?
    /// Last generation error message, shown to the user.
    @Published var lastError: String?
    /// Path to the output directory (temp, before persistence).
    var outputDirectory: URL?

    init(id: UUID = UUID(), configuration: PuzzleConfiguration) {
        self.id = id
        self.configuration = configuration
    }

    var hasGeneratedPieces: Bool { !pieces.isEmpty }

    /// Human-readable label, e.g. "5x5 (25 pieces)".
    var displayName: String {
        let grid = "\(configuration.columns)x\(configuration.rows)"
        if hasGeneratedPieces {
            return "\(grid) - \(pieces.count) pieces"
        }
        return grid
    }

    /// Removes the temp output directory from disk.
    func cleanupOutputDirectory() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        outputDirectory = nil
    }
}

extension PuzzleCut: Equatable {
    nonisolated static func == (lhs: PuzzleCut, rhs: PuzzleCut) -> Bool {
        lhs.id == rhs.id
    }
}

extension PuzzleCut: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
