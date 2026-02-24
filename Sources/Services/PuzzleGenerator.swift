import AppKit
import Foundation

/// Metadata returned by the piecemaker Python script.
struct PiecemakerMetadata: Codable {
    let piece_count: Int
    let image_width: Int
    let image_height: Int
    let requested_pieces: Int
    let pieces: [PiecemakerPiece]
    let error: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.piece_count = try container.decodeIfPresent(Int.self, forKey: .piece_count) ?? 0
        self.image_width = try container.decodeIfPresent(Int.self, forKey: .image_width) ?? 0
        self.image_height = try container.decodeIfPresent(Int.self, forKey: .image_height) ?? 0
        self.requested_pieces = try container.decodeIfPresent(Int.self, forKey: .requested_pieces) ?? 0
        self.pieces = try container.decodeIfPresent([PiecemakerPiece].self, forKey: .pieces) ?? []
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct PiecemakerPiece: Codable {
    let id: Int
    let filename: String
    let x1: Int
    let y1: Int
    let x2: Int
    let y2: Int
    let width: Int
    let height: Int
    let type: String
    let neighbours: [Int]
}

/// Result of puzzle generation.
struct GenerationResult: Sendable {
    let pieces: [PuzzlePiece]
    let linesImage: NSImage?
    let outputDirectory: URL
    let actualPieceCount: Int
}

/// Generates jigsaw puzzle pieces using the piecemaker Python library.
/// This delegates the hard geometry work (bezier curves, image clipping)
/// to a battle-tested library that produces realistic jigsaw shapes.
actor PuzzleGenerator {

    func generate(
        image: NSImage,
        imageURL: URL?,
        configuration: PuzzleConfiguration,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> GenerationResult? {
        var config = configuration
        config.validate()

        let numPieces = config.rows * config.columns

        // Save the image to a temporary file if we don't have a URL
        let tempImageURL: URL
        let needsCleanup: Bool

        if let existingURL = imageURL, FileManager.default.fileExists(atPath: existingURL.path) {
            tempImageURL = existingURL
            needsCleanup = false
        } else {
            // Write image to temp file
            let tempDir = FileManager.default.temporaryDirectory
            tempImageURL = tempDir.appendingPathComponent("puzzle_input_\(UUID().uuidString).png")
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            do {
                try pngData.write(to: tempImageURL)
            } catch {
                return nil
            }
            needsCleanup = true
        }

        defer {
            if needsCleanup {
                try? FileManager.default.removeItem(at: tempImageURL)
            }
        }

        // Output directory
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jigsaw_output_\(UUID().uuidString)")

        onProgress(0.1)

        // Find the Python script (bundled with the app)
        let scriptPath = findScript()
        guard let scriptPath = scriptPath else {
            return nil
        }

        // Run the Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", scriptPath,
            tempImageURL.path, outputDir.path, String(numPieces)
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        onProgress(0.3)

        // Wait for completion
        process.waitUntilExit()

        onProgress(0.7)

        guard process.terminationStatus == 0 else {
            return nil
        }

        // Read stdout JSON
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let metadata = try? JSONDecoder().decode(PiecemakerMetadata.self, from: outputData) else {
            return nil
        }

        if metadata.error != nil {
            return nil
        }

        onProgress(0.8)

        // Load piece images and build PuzzlePiece models
        let piecesDir = outputDir.appendingPathComponent("pieces")
        var pieces: [PuzzlePiece] = []

        for (index, pMeta) in metadata.pieces.enumerated() {
            let imagePath = piecesDir.appendingPathComponent(pMeta.filename)
            let pieceImage = NSImage(contentsOf: imagePath)

            let pieceType: PieceType
            switch pMeta.type {
            case "corner": pieceType = .corner
            case "edge": pieceType = .edge
            default: pieceType = .interior
            }

            let piece = PuzzlePiece(
                id: UUID(),
                pieceIndex: pMeta.id,
                row: pMeta.y1,
                col: pMeta.x1,
                x1: pMeta.x1, y1: pMeta.y1,
                x2: pMeta.x2, y2: pMeta.y2,
                pieceWidth: pMeta.width,
                pieceHeight: pMeta.height,
                pieceType: pieceType,
                neighbourIDs: pMeta.neighbours,
                image: pieceImage
            )
            pieces.append(piece)

            let progress = 0.8 + 0.2 * Double(index + 1) / Double(metadata.pieces.count)
            onProgress(progress)
        }

        // Load the lines overlay image
        let linesPath = outputDir.appendingPathComponent("lines.png")
        let linesImage = NSImage(contentsOf: linesPath)

        return GenerationResult(
            pieces: pieces,
            linesImage: linesImage,
            outputDirectory: outputDir,
            actualPieceCount: metadata.piece_count
        )
    }

    /// Find the generate_puzzle.py script relative to the executable.
    private func findScript() -> String? {
        // When running via `swift run`, the executable is in .build/
        // The script is in Scripts/ relative to the project root
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)

        // Try relative to executable (for swift run from project root)
        let projectRoot = executableURL
            .deletingLastPathComponent()  // debug/
            .deletingLastPathComponent()  // arm64-.../
            .deletingLastPathComponent()  // .build/

        let scriptPath = projectRoot.appendingPathComponent("Scripts/generate_puzzle.py").path
        if FileManager.default.fileExists(atPath: scriptPath) {
            return scriptPath
        }

        // Try current working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/Scripts/generate_puzzle.py"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        // Try hardcoded path as fallback
        let hardcodedPath = "/Users/mihalydani/Local/jigsaw-puzzle-generator/Scripts/generate_puzzle.py"
        if FileManager.default.fileExists(atPath: hardcodedPath) {
            return hardcodedPath
        }

        return nil
    }
}
