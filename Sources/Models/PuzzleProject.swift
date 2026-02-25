import AppKit
import Combine
import Foundation

/// Represents a single puzzle project - one source image and its generated pieces.
@MainActor
class PuzzleProject: ObservableObject, Identifiable {
    let id: UUID
    var name: String
    var sourceImage: NSImage
    var sourceImageURL: URL?

    @Published var configuration: PuzzleConfiguration
    @Published var pieces: [PuzzlePiece] = []
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    /// The puzzle cut lines overlay image from piecemaker.
    @Published var linesImage: NSImage?
    /// Last generation error message, shown to the user.
    @Published var lastError: String?
    /// Path to the piecemaker output directory for this generation.
    var outputDirectory: URL?

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

    init(name: String, sourceImage: NSImage, sourceImageURL: URL? = nil) {
        self.id = UUID()
        self.name = name
        self.sourceImage = sourceImage
        self.sourceImageURL = sourceImageURL
        self.configuration = PuzzleConfiguration()
    }

    var hasGeneratedPieces: Bool { !pieces.isEmpty }

    /// Removes the piecemaker output directory from disk.
    func cleanupOutputDirectory() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.removeItem(at: dir)
        outputDirectory = nil
    }
}

extension PuzzleProject: Equatable {
    nonisolated static func == (lhs: PuzzleProject, rhs: PuzzleProject) -> Bool {
        lhs.id == rhs.id
    }
}

extension PuzzleProject: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
