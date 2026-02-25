import AppKit
import Combine
import Foundation

/// Represents a single source image within a project.
/// Contains the source image data and a list of puzzle cuts at different grid sizes.
@MainActor
class PuzzleImage: ObservableObject, Identifiable {
    let id: UUID
    var name: String
    var sourceImage: NSImage
    var sourceImageURL: URL?
    /// Relative path to the permanent source image copy within the project directory.
    /// Set after the image is persisted to disk by ProjectStore.
    var sourceImagePath: String?
    /// Attribution and licence info (non-nil for Openverse images).
    var attribution: ImageAttribution?
    /// Puzzle cuts at different grid sizes.
    @Published var cuts: [PuzzleCut] = []

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
