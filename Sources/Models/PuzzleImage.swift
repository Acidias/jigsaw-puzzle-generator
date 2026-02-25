import AppKit
import Combine
import Foundation

/// Represents a single source image and its generated puzzle pieces.
/// This is the image-level unit within a PuzzleProject container.
@MainActor
class PuzzleImage: ObservableObject, Identifiable {
    let id: UUID
    var name: String
    var sourceImage: NSImage
    var sourceImageURL: URL?
    /// Relative path to the permanent source image copy within the project directory.
    /// Set after the image is persisted to disk by ProjectStore.
    var sourceImagePath: String?

    @Published var configuration: PuzzleConfiguration
    @Published var pieces: [PuzzlePiece] = []
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    /// The puzzle cut lines overlay image.
    @Published var linesImage: NSImage?
    /// Last generation error message, shown to the user.
    @Published var lastError: String?
    /// Path to the output directory for this generation (temp, before persistence).
    var outputDirectory: URL?
    /// Attribution and licence info (non-nil for Openverse images).
    var attribution: ImageAttribution?

    /// Image dimensions in pixels (not points) for accurate metadata.
    var imageWidth: Int {
        guard let rep = sourceImage.representations.first else {
            return Int(sourceImage.size.width)
        }
        return rep.pixelsWide > 0 ? rep.pixelsWide : Int(sourceImage.size.width)
    }
    var imageHeight: Int {
        guard let rep = sourceImage.representations.first else {
            return Int(sourceImage.size.height)
        }
        return rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(sourceImage.size.height)
    }

    init(id: UUID = UUID(), name: String, sourceImage: NSImage, sourceImageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.sourceImage = sourceImage
        self.sourceImageURL = sourceImageURL
        self.configuration = PuzzleConfiguration()
    }

    var hasGeneratedPieces: Bool { !pieces.isEmpty }

    /// Removes the output directory from disk.
    func cleanupOutputDirectory() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        outputDirectory = nil
    }
}

extension PuzzleImage: Equatable {
    nonisolated static func == (lhs: PuzzleImage, rhs: PuzzleImage) -> Bool {
        lhs.id == rhs.id
    }
}

extension PuzzleImage: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
