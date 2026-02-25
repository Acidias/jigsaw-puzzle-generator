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
///     cuts/<cut-uuid>/
///       <image-uuid>/
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

    static func cutDirectory(projectID: UUID, cutID: UUID) -> URL {
        projectDirectory(for: projectID)
            .appendingPathComponent("cuts")
            .appendingPathComponent(cutID.uuidString)
    }

    static func cutImageDirectory(projectID: UUID, cutID: UUID, imageID: UUID) -> URL {
        cutDirectory(projectID: projectID, cutID: cutID)
            .appendingPathComponent(imageID.uuidString)
    }

    static func piecesDirectory(projectID: UUID, cutID: UUID, imageID: UUID) -> URL {
        cutImageDirectory(projectID: projectID, cutID: cutID, imageID: imageID)
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
                    attribution: image.attribution
                )
            },
            cuts: project.cuts.map { cut in
                CutManifest(
                    id: cut.id,
                    configuration: cut.configuration,
                    imageResults: cut.imageResults.map { result in
                        CutImageResultManifest(
                            id: result.id,
                            imageID: result.imageID,
                            imageName: result.imageName,
                            pieces: result.pieces.map { piece in
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
                            hasLinesOverlay: result.linesImage != nil,
                            hasNormalisedSource: result.normalisedSourceImage != nil
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

            // Load images
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

                project.images.append(puzzleImage)
            }

            // Load cuts
            for cutManifest in manifest.cuts {
                let cut = PuzzleCut(id: cutManifest.id, configuration: cutManifest.configuration)

                for resultManifest in cutManifest.imageResults {
                    let imageResult = CutImageResult(
                        id: resultManifest.id,
                        imageID: resultManifest.imageID,
                        imageName: resultManifest.imageName
                    )

                    let cutPiecesDir = piecesDirectory(
                        projectID: manifest.id,
                        cutID: cutManifest.id,
                        imageID: resultManifest.imageID
                    )

                    imageResult.pieces = resultManifest.pieces.map { pm in
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

                    let cutImgDir = cutImageDirectory(
                        projectID: manifest.id,
                        cutID: cutManifest.id,
                        imageID: resultManifest.imageID
                    )

                    if resultManifest.hasLinesOverlay {
                        let linesURL = cutImgDir.appendingPathComponent("lines.png")
                        if let linesImage = NSImage(contentsOf: linesURL) {
                            imageResult.linesImage = linesImage
                        }
                    }

                    if resultManifest.hasNormalisedSource {
                        let normURL = cutImgDir.appendingPathComponent("normalised_source.png")
                        if let normImage = NSImage(contentsOf: normURL) {
                            imageResult.normalisedSourceImage = normImage
                        }
                    }

                    cut.imageResults.append(imageResult)
                }

                project.cuts.append(cut)
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

    static func deleteCut(projectID: UUID, cutID: UUID) {
        let dir = cutDirectory(projectID: projectID, cutID: cutID)
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
    static func moveGeneratedPieces(for imageResult: CutImageResult, cutID: UUID, in project: PuzzleProject) {
        guard let tempDir = imageResult.outputDirectory else { return }
        let permanentDir = piecesDirectory(projectID: project.id, cutID: cutID, imageID: imageResult.imageID)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: permanentDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create pieces directory: \(error)")
            return
        }

        var updatedPieces: [PuzzlePiece] = []
        for piece in imageResult.pieces {
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

        imageResult.pieces = updatedPieces

        // Clean up temp directory
        try? fm.removeItem(at: tempDir)
        imageResult.outputDirectory = nil
    }

    /// Saves the lines overlay image to the image result's permanent directory.
    @MainActor
    static func saveLinesOverlay(for imageResult: CutImageResult, cutID: UUID, in project: PuzzleProject) {
        guard let linesImage = imageResult.linesImage else { return }
        let cutImgDir = cutImageDirectory(projectID: project.id, cutID: cutID, imageID: imageResult.imageID)
        let linesURL = cutImgDir.appendingPathComponent("lines.png")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: cutImgDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create cut image directory: \(error)")
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

    /// Saves the normalised (cropped+resized) source image for a cut image result.
    @MainActor
    static func saveNormalisedSource(for imageResult: CutImageResult, cutID: UUID, in project: PuzzleProject) {
        guard let normImage = imageResult.normalisedSourceImage else { return }
        let cutImgDir = cutImageDirectory(projectID: project.id, cutID: cutID, imageID: imageResult.imageID)
        let normURL = cutImgDir.appendingPathComponent("normalised_source.png")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: cutImgDir, withIntermediateDirectories: true)
        } catch {
            print("ProjectStore: Failed to create cut image directory: \(error)")
            return
        }

        if let tiffData = normImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: normURL)
            } catch {
                print("ProjectStore: Failed to save normalised source: \(error)")
            }
        }
    }
}
