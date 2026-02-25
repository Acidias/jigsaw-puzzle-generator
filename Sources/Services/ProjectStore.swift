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
///       cuts/<cut-uuid>/
///         pieces/piece_0.png ...
///         lines.png
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

    static func cutDirectory(projectID: UUID, imageID: UUID, cutID: UUID) -> URL {
        imageDirectory(projectID: projectID, imageID: imageID)
            .appendingPathComponent("cuts")
            .appendingPathComponent(cutID.uuidString)
    }

    static func piecesDirectory(projectID: UUID, imageID: UUID, cutID: UUID) -> URL {
        cutDirectory(projectID: projectID, imageID: imageID, cutID: cutID)
            .appendingPathComponent("pieces")
    }

    // MARK: - Save

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
                    attribution: image.attribution,
                    cuts: image.cuts.map { cut in
                        CutManifest(
                            id: cut.id,
                            configuration: cut.configuration,
                            pieces: cut.pieces.map { piece in
                                PieceManifest(
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
                                    imageFilename: piece.imagePath?.lastPathComponent ?? "piece_\(piece.pieceIndex).png"
                                )
                            },
                            hasLinesOverlay: cut.linesImage != nil
                        )
                    }
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
                puzzleImage.attribution = imageManifest.attribution

                // Load cuts
                for cutManifest in imageManifest.cuts {
                    let cut = PuzzleCut(id: cutManifest.id, configuration: cutManifest.configuration)
                    let cutPiecesDir = piecesDirectory(
                        projectID: manifest.id,
                        imageID: imageManifest.id,
                        cutID: cutManifest.id
                    )

                    cut.pieces = cutManifest.pieces.map { pm in
                        let piecePath = cutPiecesDir.appendingPathComponent(pm.imageFilename)
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

                    if cutManifest.hasLinesOverlay {
                        let cutDir = cutDirectory(
                            projectID: manifest.id,
                            imageID: imageManifest.id,
                            cutID: cutManifest.id
                        )
                        let linesURL = cutDir.appendingPathComponent("lines.png")
                        if let linesImage = NSImage(contentsOf: linesURL) {
                            cut.linesImage = linesImage
                        }
                    }

                    puzzleImage.cuts.append(cut)
                }

                project.images.append(puzzleImage)
            }

            projects.append(project)
        }

        projects.sort { $0.createdAt < $1.createdAt }
        return projects
    }

    // MARK: - Delete

    static func deleteProject(id: UUID) {
        let dir = projectDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    static func deleteImage(projectID: UUID, imageID: UUID) {
        let dir = imageDirectory(projectID: projectID, imageID: imageID)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - File Operations

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

        let sourceFilename: String
        if let url = image.sourceImageURL {
            sourceFilename = "source.\(url.pathExtension.lowercased().isEmpty ? "png" : url.pathExtension.lowercased())"
        } else {
            sourceFilename = "source.png"
        }

        let destURL = imgDir.appendingPathComponent(sourceFilename)

        if fm.fileExists(atPath: destURL.path) {
            image.sourceImagePath = sourceFilename
            return
        }

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
    static func moveGeneratedPieces(for cut: PuzzleCut, imageID: UUID, in project: PuzzleProject) {
        guard let tempDir = cut.outputDirectory else { return }
        let permanentDir = piecesDirectory(projectID: project.id, imageID: imageID, cutID: cut.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: permanentDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create pieces directory: \(error)")
            return
        }

        var updatedPieces: [PuzzlePiece] = []
        for piece in cut.pieces {
            guard let sourcePath = piece.imagePath else {
                updatedPieces.append(piece)
                continue
            }

            let filename = sourcePath.lastPathComponent
            let destURL = permanentDir.appendingPathComponent(filename)

            if sourcePath.path == destURL.path {
                updatedPieces.append(piece)
                continue
            }

            do {
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourcePath, to: destURL)

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

        cut.pieces = updatedPieces

        // Clean up temp directory
        try? fm.removeItem(at: tempDir)
        cut.outputDirectory = nil
    }

    /// Saves the lines overlay image to the cut's permanent directory.
    @MainActor
    static func saveLinesOverlay(for cut: PuzzleCut, imageID: UUID, in project: PuzzleProject) {
        guard let linesImage = cut.linesImage else { return }
        let cutDir = cutDirectory(projectID: project.id, imageID: imageID, cutID: cut.id)
        let linesURL = cutDir.appendingPathComponent("lines.png")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: cutDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create cut directory: \(error)")
            return
        }

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
