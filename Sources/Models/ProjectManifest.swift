import Foundation

/// Codable manifest for persisting a project to disk.
struct ProjectManifest: Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var images: [ImageManifest]
    var cuts: [CutManifest]
}

/// Codable manifest for a single image within a project.
struct ImageManifest: Codable {
    let id: UUID
    var name: String
    var sourceImageFilename: String
    var attribution: ImageAttribution?
}

/// Codable manifest for one puzzle cut (a grid configuration applied to all project images).
struct CutManifest: Codable {
    let id: UUID
    var configuration: PuzzleConfiguration
    var imageResults: [CutImageResultManifest]
}

/// Codable manifest for one image's results within a cut.
struct CutImageResultManifest: Codable {
    let id: UUID
    let imageID: UUID
    var imageName: String
    var pieces: [PieceManifest]
    var hasLinesOverlay: Bool
}

/// Codable manifest for a single puzzle piece.
struct PieceManifest: Codable {
    let id: UUID
    let pieceIndex: Int
    let row: Int
    let col: Int
    let x1: Int
    let y1: Int
    let x2: Int
    let y2: Int
    let pieceWidth: Int
    let pieceHeight: Int
    let pieceType: PieceType
    let neighbourIDs: [Int]
    let imageFilename: String
}
