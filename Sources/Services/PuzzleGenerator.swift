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

/// Errors that can occur during puzzle generation.
enum GenerationError: Error, LocalizedError {
    case imageEncodingFailed
    case scriptNotFound
    case processLaunchFailed(String)
    case piecemakerFailed(stderr: String, exitCode: Int32)
    case jsonParseFailed(String)
    case noPiecesGenerated

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode the source image as PNG."
        case .scriptNotFound:
            return "Could not find generate_puzzle.py. Make sure the script exists in the Scripts/ directory."
        case .processLaunchFailed(let reason):
            return "Failed to launch the Python process: \(reason)"
        case .piecemakerFailed(let stderr, let exitCode):
            let detail = stderr.isEmpty ? "No error output captured." : stderr
            return "piecemaker failed (exit code \(exitCode)):\n\(detail)"
        case .jsonParseFailed(let detail):
            return "Failed to parse piecemaker output: \(detail)"
        case .noPiecesGenerated:
            return "piecemaker returned no pieces. The image may be too small for the requested grid size."
        }
    }
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
    ) async -> Result<GenerationResult, GenerationError> {
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
                return .failure(.imageEncodingFailed)
            }
            do {
                try pngData.write(to: tempImageURL)
            } catch {
                return .failure(.imageEncodingFailed)
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
        guard let scriptPath = findScript() else {
            return .failure(.scriptNotFound)
        }

        // Run the Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", scriptPath,
            tempImageURL.path, outputDir.path, String(numPieces)
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(.processLaunchFailed(error.localizedDescription))
        }

        onProgress(0.3)

        // Wait for completion using a continuation instead of blocking
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        onProgress(0.7)

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            return .failure(.piecemakerFailed(stderr: stderrString, exitCode: process.terminationStatus))
        }

        // Read stdout JSON
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        let metadata: PiecemakerMetadata
        do {
            metadata = try JSONDecoder().decode(PiecemakerMetadata.self, from: outputData)
        } catch {
            let rawOutput = String(data: outputData, encoding: .utf8) ?? "<binary data>"
            return .failure(.jsonParseFailed("\(error.localizedDescription)\nRaw output: \(rawOutput.prefix(500))"))
        }

        if let errorMessage = metadata.error {
            return .failure(.piecemakerFailed(stderr: errorMessage, exitCode: 0))
        }

        onProgress(0.8)

        // Build PuzzlePiece models with file paths (lazy image loading)
        let piecesDir = outputDir.appendingPathComponent("pieces")
        var pieces: [PuzzlePiece] = []

        guard !metadata.pieces.isEmpty else {
            return .failure(.noPiecesGenerated)
        }

        for (index, pMeta) in metadata.pieces.enumerated() {
            let imagePath = piecesDir.appendingPathComponent(pMeta.filename)

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
                imagePath: imagePath
            )
            pieces.append(piece)

            let progress = 0.8 + 0.2 * Double(index + 1) / Double(metadata.pieces.count)
            onProgress(progress)
        }

        // Load the lines overlay image
        let linesPath = outputDir.appendingPathComponent("lines.png")
        let linesImage = NSImage(contentsOf: linesPath)

        return .success(GenerationResult(
            pieces: pieces,
            linesImage: linesImage,
            outputDirectory: outputDir,
            actualPieceCount: metadata.piece_count
        ))
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

        return nil
    }
}
