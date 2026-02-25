import AppKit
import Foundation

/// Handles persistence of projects to ~/Library/Application Support/JigsawPuzzleGenerator/.
/// Stateless enum - all methods are static.
///
/// Disk layout:
///   projects/<project-uuid>/
///     manifest.json
///     images/<image-uuid>/
///       source.<ext>
///       pieces/piece_0.png ...
///       lines.png
enum ProjectStore {

    // MARK: - Paths

    static var appSupportDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("JigsawPuzzleGenerator")
    }

    static var projectsDirectory: URL {
        appSupportDirectory.appendingPathComponent("projects")
    }

    static func projectDirectory(for projectID: UUID) -> URL {
        projectsDirectory.appendingPathComponent(projectID.uuidString)
    }

    static func imageDirectory(projectID: UUID, imageID: UUID) -> URL {
        projectDirectory(for: projectID)
            .appendingPathComponent("images")
            .appendingPathComponent(imageID.uuidString)
    }

    static func piecesDirectory(projectID: UUID, imageID: UUID) -> URL {
        imageDirectory(projectID: projectID, imageID: imageID)
            .appendingPathComponent("pieces")
    }

    // MARK: - Save

    /// Saves a project's manifest to disk.
    @MainActor
    static func saveProject(_ project: PuzzleProject) {
        let projectDir = projectDirectory(for: project.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create project directory: \(error)")
            return
        }

        let manifest = ProjectManifest(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            images: project.images.map { image in
                ImageManifest(
                    id: image.id,
                    name: image.name,
                    sourceImageFilename: image.sourceImagePath ?? "",
                    configuration: image.configuration,
                    pieces: image.pieces.map { piece in
                        PieceManifest(
                            id: piece.id,
                            pieceIndex: piece.pieceIndex,
                            row: piece.row,
                            col: piece.col,
                            x1: piece.x1,
                            y1: piece.y1,
                            x2: piece.x2,
                            y2: piece.y2,
                            pieceWidth: piece.pieceWidth,
                            pieceHeight: piece.pieceHeight,
                            pieceType: piece.pieceType,
                            neighbourIDs: piece.neighbourIDs,
                            imageFilename: piece.imagePath?.lastPathComponent ?? "piece_\(piece.pieceIndex).png"
                        )
                    },
                    attribution: image.attribution,
                    hasLinesOverlay: image.linesImage != nil
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = projectDir.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL)
        } catch {
            print("ProjectStore: Failed to write manifest: \(error)")
        }
    }

    // MARK: - Load

    /// Loads all persisted projects from disk.
    @MainActor
    static func loadAllProjects() -> [PuzzleProject] {
        let fm = FileManager.default
        let projectsDir = projectsDirectory

        guard fm.fileExists(atPath: projectsDir.path) else { return [] }

        var projects: [PuzzleProject] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        for dir in contents {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }

            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(ProjectManifest.self, from: data) else { continue }

            let project = PuzzleProject(
                id: manifest.id,
                name: manifest.name,
                createdAt: manifest.createdAt
            )

            for imageManifest in manifest.images {
                let imgDir = imageDirectory(projectID: manifest.id, imageID: imageManifest.id)
                let sourceURL = imgDir.appendingPathComponent(imageManifest.sourceImageFilename)

                // Load source image from permanent storage
                guard let sourceImage = NSImage(contentsOf: sourceURL) else {
                    print("ProjectStore: Could not load source image at \(sourceURL.path), skipping")
                    continue
                }

                let puzzleImage = PuzzleImage(
                    id: imageManifest.id,
                    name: imageManifest.name,
                    sourceImage: sourceImage,
                    sourceImageURL: sourceURL
                )
                puzzleImage.sourceImagePath = imageManifest.sourceImageFilename
                puzzleImage.configuration = imageManifest.configuration
                puzzleImage.attribution = imageManifest.attribution

                // Load pieces with resolved paths
                let piecesDir = imgDir.appendingPathComponent("pieces")
                puzzleImage.pieces = imageManifest.pieces.map { pm in
                    let piecePath = piecesDir.appendingPathComponent(pm.imageFilename)
                    return PuzzlePiece(
                        id: pm.id,
                        pieceIndex: pm.pieceIndex,
                        row: pm.row,
                        col: pm.col,
                        x1: pm.x1, y1: pm.y1,
                        x2: pm.x2, y2: pm.y2,
                        pieceWidth: pm.pieceWidth,
                        pieceHeight: pm.pieceHeight,
                        pieceType: pm.pieceType,
                        neighbourIDs: pm.neighbourIDs,
                        imagePath: fm.fileExists(atPath: piecePath.path) ? piecePath : nil
                    )
                }

                // Load lines overlay if it exists
                if imageManifest.hasLinesOverlay {
                    let linesURL = imgDir.appendingPathComponent("lines.png")
                    if let linesImage = NSImage(contentsOf: linesURL) {
                        puzzleImage.linesImage = linesImage
                    }
                }

                project.images.append(puzzleImage)
            }

            projects.append(project)
        }

        // Sort by creation date
        projects.sort { $0.createdAt < $1.createdAt }
        return projects
    }

    // MARK: - Delete

    /// Removes a project's entire directory from disk.
    static func deleteProject(id: UUID) {
        let dir = projectDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Removes a single image directory from a project on disk.
    static func deleteImage(projectID: UUID, imageID: UUID) {
        let dir = imageDirectory(projectID: projectID, imageID: imageID)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - File Operations

    /// Copies (or encodes) the source image into the project's permanent storage.
    @MainActor
    static func copySourceImage(_ image: PuzzleImage, to project: PuzzleProject) {
        let imgDir = imageDirectory(projectID: project.id, imageID: image.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: imgDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create image directory: \(error)")
            return
        }

        // Determine filename
        let sourceFilename: String
        if let url = image.sourceImageURL {
            sourceFilename = "source.\(url.pathExtension.lowercased().isEmpty ? "png" : url.pathExtension.lowercased())"
        } else {
            sourceFilename = "source.png"
        }

        let destURL = imgDir.appendingPathComponent(sourceFilename)

        // If already copied, skip
        if fm.fileExists(atPath: destURL.path) {
            image.sourceImagePath = sourceFilename
            return
        }

        // Try to copy from original URL
        if let sourceURL = image.sourceImageURL, fm.fileExists(atPath: sourceURL.path) {
            do {
                try fm.copyItem(at: sourceURL, to: destURL)
                image.sourceImagePath = sourceFilename
                image.sourceImageURL = destURL
                return
            } catch {
                print("ProjectStore: Failed to copy source image: \(error)")
            }
        }

        // Fallback: encode NSImage as PNG
        if let tiffData = image.sourceImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                let fallbackURL = imgDir.appendingPathComponent("source.png")
                try pngData.write(to: fallbackURL)
                image.sourceImagePath = "source.png"
                image.sourceImageURL = fallbackURL
            } catch {
                print("ProjectStore: Failed to encode source image: \(error)")
            }
        }
    }

    /// Moves generated piece PNGs from the temp output directory to permanent storage.
    @MainActor
    static func moveGeneratedPieces(for image: PuzzleImage, in project: PuzzleProject) {
        guard let tempDir = image.outputDirectory else { return }
        let permanentDir = piecesDirectory(projectID: project.id, imageID: image.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: permanentDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create pieces directory: \(error)")
            return
        }

        // Move each piece file
        var updatedPieces: [PuzzlePiece] = []
        for piece in image.pieces {
            guard let sourcePath = piece.imagePath else {
                updatedPieces.append(piece)
                continue
            }

            let filename = sourcePath.lastPathComponent
            let destURL = permanentDir.appendingPathComponent(filename)

            // If already in permanent location, skip
            if sourcePath.path == destURL.path {
                updatedPieces.append(piece)
                continue
            }

            do {
                // Remove existing file if present (e.g. from a previous generation)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourcePath, to: destURL)

                // Create updated piece with new path
                let updated = PuzzlePiece(
                    id: piece.id,
                    pieceIndex: piece.pieceIndex,
                    row: piece.row,
                    col: piece.col,
                    x1: piece.x1, y1: piece.y1,
                    x2: piece.x2, y2: piece.y2,
                    pieceWidth: piece.pieceWidth,
                    pieceHeight: piece.pieceHeight,
                    pieceType: piece.pieceType,
                    neighbourIDs: piece.neighbourIDs,
                    imagePath: destURL
                )
                updatedPieces.append(updated)
            } catch {
                print("ProjectStore: Failed to copy piece \(filename): \(error)")
                updatedPieces.append(piece)
            }
        }

        image.pieces = updatedPieces

        // Clean up temp directory
        try? fm.removeItem(at: tempDir)
        image.outputDirectory = nil
    }

    /// Saves the lines overlay image to the image's permanent directory.
    @MainActor
    static func saveLinesOverlay(for image: PuzzleImage, in project: PuzzleProject) {
        guard let linesImage = image.linesImage else { return }
        let imgDir = imageDirectory(projectID: project.id, imageID: image.id)
        let linesURL = imgDir.appendingPathComponent("lines.png")

        if let tiffData = linesImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: linesURL)
            } catch {
                print("ProjectStore: Failed to save lines overlay: \(error)")
            }
        }
    }
}
