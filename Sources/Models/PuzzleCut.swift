import AppKit
import Combine
import Foundation

/// A project-level puzzle cut - a grid configuration applied to all images in a project.
/// Contains a CutImageResult per source image with pieces and overlay for each.
@MainActor
class PuzzleCut: ObservableObject, Identifiable {
    let id: UUID
    @Published var configuration: PuzzleConfiguration
    @Published var imageResults: [CutImageResult] = []

    init(id: UUID = UUID(), configuration: PuzzleConfiguration) {
        self.id = id
        self.configuration = configuration
    }

    /// True if any image result is currently generating.
    var isGenerating: Bool {
        imageResults.contains { $0.isGenerating }
    }

    /// Overall progress across all image results (0.0 to 1.0).
    var overallProgress: Double {
        guard !imageResults.isEmpty else { return 0 }
        let total = imageResults.reduce(0.0) { sum, result in
            if result.hasGeneratedPieces || result.lastError != nil {
                return sum + 1.0
            }
            return sum + result.progress
        }
        return total / Double(imageResults.count)
    }

    /// Total piece count across all image results.
    var totalPieceCount: Int {
        imageResults.reduce(0) { $0 + $1.pieces.count }
    }

    var hasGeneratedPieces: Bool {
        imageResults.contains { $0.hasGeneratedPieces }
    }

    /// Human-readable label, e.g. "5x5 - 50 pieces".
    var displayName: String {
        let grid = "\(configuration.columns)x\(configuration.rows)"
        let count = totalPieceCount
        if count > 0 {
            return "\(grid) - \(count) pieces"
        }
        return grid
    }

    /// Removes temp output directories from all image results.
    func cleanupOutputDirectories() {
        for result in imageResults {
            result.cleanupOutputDirectory()
        }
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
