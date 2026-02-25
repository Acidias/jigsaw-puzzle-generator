import AppKit
import Combine
import Foundation

/// Per-image result within a project-level cut.
/// Each CutImageResult tracks the generation output (pieces, lines overlay)
/// for one source image under a shared grid configuration.
@MainActor
class CutImageResult: ObservableObject, Identifiable {
    let id: UUID
    /// Reference to the source PuzzleImage.
    let imageID: UUID
    /// Denormalised image name for display without resolving the PuzzleImage.
    var imageName: String
    @Published var pieces: [PuzzlePiece] = []
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    /// The puzzle cut lines overlay image for this image.
    @Published var linesImage: NSImage?
    /// The normalised (cropped+resized) source image when AI normalisation was used.
    @Published var normalisedSourceImage: NSImage?
    /// Last generation error message, shown to the user.
    @Published var lastError: String?
    /// Path to the temp output directory (before persistence).
    var outputDirectory: URL?

    init(id: UUID = UUID(), imageID: UUID, imageName: String) {
        self.id = id
        self.imageID = imageID
        self.imageName = imageName
    }

    var hasGeneratedPieces: Bool { !pieces.isEmpty }

    /// Removes the temp output directory from disk.
    func cleanupOutputDirectory() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        outputDirectory = nil
    }
}

extension CutImageResult: Equatable {
    nonisolated static func == (lhs: CutImageResult, rhs: CutImageResult) -> Bool {
        lhs.id == rhs.id
    }
}

extension CutImageResult: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
