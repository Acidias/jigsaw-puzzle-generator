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

    /// Image dimensions for display.
    var imageWidth: Int { Int(sourceImage.size.width) }
    var imageHeight: Int { Int(sourceImage.size.height) }

    init(name: String, sourceImage: NSImage, sourceImageURL: URL? = nil) {
        self.id = UUID()
        self.name = name
        self.sourceImage = sourceImage
        self.sourceImageURL = sourceImageURL
        self.configuration = PuzzleConfiguration()
    }

    var hasGeneratedPieces: Bool { !pieces.isEmpty }
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
