import AppKit
import Foundation
import ImageIO

/// Result of puzzle generation.
struct GenerationResult: Sendable {
    let pieces: [PuzzlePiece]
    let linesImage: NSImage?
    /// The normalised (cropped+resized) source image when AI normalisation is active.
    let normalisedSourceImage: NSImage?
    let outputDirectory: URL
    let actualPieceCount: Int
}

/// Errors that can occur during puzzle generation.
enum GenerationError: Error, LocalizedError {
    case imageLoadFailed
    case noPiecesGenerated
    case outputDirectoryFailed(String)
    case pieceExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load the source image for processing."
        case .noPiecesGenerated:
            return "No pieces were generated. The image may be too small for the requested grid size."
        case .outputDirectoryFailed(let reason):
            return "Failed to create output directory: \(reason)"
        case .pieceExportFailed(let reason):
            return "Failed to export a puzzle piece: \(reason)"
        }
    }
}

/// Generates jigsaw puzzle pieces using native Swift bezier curve geometry.
/// Builds CGPath outlines for each piece, clips the source image, and writes
/// transparent PNGs to disk for lazy loading.
actor PuzzleGenerator {

    func generate(
        image: NSImage,
        imageURL: URL?,
        configuration: PuzzleConfiguration,
        gridEdges existingEdges: GridEdges? = nil,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> Result<GenerationResult, GenerationError> {
        var config = configuration
        config.validate()

        let rows = config.rows
        let cols = config.columns

        onProgress(0.02)

        // Get CGImage from the source, preferring the file on disk for best quality
        let sourceImage: CGImage
        if let url = imageURL,
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let loaded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            sourceImage = loaded
        } else if let cgImage = cgImageFromNSImage(image) {
            sourceImage = cgImage
        } else {
            return .failure(.imageLoadFailed)
        }

        onProgress(0.05)

        // Prepare working image: normalise or upscale
        let workingImage: CGImage
        if let pieceSize = config.pieceSize {
            // AI normalisation: crop to grid aspect ratio, resize to exact dimensions
            let cropped = ImageScaler.cropToAspectRatio(sourceImage, cols: cols, rows: rows)
            let targetWidth = cols * pieceSize
            let targetHeight = rows * pieceSize
            workingImage = ImageScaler.resize(cropped, toWidth: targetWidth, height: targetHeight)
        } else {
            // Standard path: upscale small images for smooth bezier edges
            workingImage = ImageScaler.upscaleIfNeeded(sourceImage)
        }
        let imageWidth = workingImage.width
        let imageHeight = workingImage.height

        // Compute cell dimensions
        let cellWidth = CGFloat(imageWidth) / CGFloat(cols)
        let cellHeight = CGFloat(imageHeight) / CGFloat(rows)

        onProgress(0.08)

        // Generate all grid edges with random tab directions (or reuse provided ones)
        let gridEdges: GridEdges
        if let existingEdges {
            gridEdges = existingEdges
        } else {
            gridEdges = GridEdges.generate(
                rows: rows,
                cols: cols,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            )
        }

        onProgress(0.10)

        // Create output directory
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jigsaw_output_\(UUID().uuidString)")
        let piecesDir = outputDir.appendingPathComponent("pieces")

        do {
            try FileManager.default.createDirectory(
                at: piecesDir,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(.outputDirectoryFailed(error.localizedDescription))
        }

        // Generate each piece: build path, clip image, save PNG
        let totalPieces = rows * cols
        var pieces: [PuzzlePiece] = []
        pieces.reserveCapacity(totalPieces)

        for row in 0..<rows {
            for col in 0..<cols {
                let pieceIndex = row * cols + col

                // Build the closed CGPath for this piece
                let piecePath = PiecePathBuilder.buildPiecePath(
                    row: row,
                    col: col,
                    rows: rows,
                    cols: cols,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    gridEdges: gridEdges
                )

                // Clip the source image and save as transparent PNG
                let filename = "piece_\(pieceIndex).png"
                let outputURL = piecesDir.appendingPathComponent(filename)

                let clipResult: PieceClipper.ClipResult
                do {
                    clipResult = try PieceClipper.clipAndSave(
                        sourceImage: workingImage,
                        piecePath: piecePath,
                        outputURL: outputURL,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                } catch {
                    return .failure(.pieceExportFailed(
                        "Piece \(pieceIndex): \(error.localizedDescription)"
                    ))
                }

                // Compute piece type from grid position
                let isTop = (row == 0)
                let isBottom = (row == rows - 1)
                let isLeft = (col == 0)
                let isRight = (col == cols - 1)
                let borderCount = [isTop, isBottom, isLeft, isRight].filter { $0 }.count

                let pieceType: PieceType
                if borderCount >= 2 {
                    pieceType = .corner
                } else if borderCount == 1 {
                    pieceType = .edge
                } else {
                    pieceType = .interior
                }

                // Compute neighbours (trivial on a grid)
                var neighbourIDs: [Int] = []
                if row > 0 { neighbourIDs.append((row - 1) * cols + col) }
                if row < rows - 1 { neighbourIDs.append((row + 1) * cols + col) }
                if col > 0 { neighbourIDs.append(row * cols + (col - 1)) }
                if col < cols - 1 { neighbourIDs.append(row * cols + (col + 1)) }

                let piece = PuzzlePiece(
                    id: UUID(),
                    pieceIndex: pieceIndex,
                    row: clipResult.y1,
                    col: clipResult.x1,
                    x1: clipResult.x1,
                    y1: clipResult.y1,
                    x2: clipResult.x2,
                    y2: clipResult.y2,
                    pieceWidth: clipResult.width,
                    pieceHeight: clipResult.height,
                    pieceType: pieceType,
                    neighbourIDs: neighbourIDs,
                    imagePath: outputURL
                )
                pieces.append(piece)

                // Report progress (0.10 to 0.90 range)
                let progress = 0.10 + 0.80 * Double(pieceIndex + 1) / Double(totalPieces)
                onProgress(progress)
            }
        }

        guard !pieces.isEmpty else {
            return .failure(.noPiecesGenerated)
        }

        // Post-processing: pad pieces to uniform canvas when normalising
        if let pieceSize = config.pieceSize {
            // Use a deterministic canvas size based on pieceSize, not the actual
            // per-image maxDim. The bezier algorithm's max tab protrusion is ~0.34
            // of the cell size (anchorCenter.y in EdgePath). An interior piece can
            // have tabs on all 4 sides, so worst-case dimension is roughly
            // pieceSize * 1.68 + 2*bleed. We use 1.75x as a safe upper bound.
            // This guarantees identical piece dimensions across ALL images.
            let canvasSize = Int(ceil(Double(pieceSize) * 1.75))

            // Determine fill colour
            let fillColour: CGColor
            switch config.pieceFill {
            case .none:
                fillColour = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
            case .black:
                fillColour = CGColor(gray: 0, alpha: 1)
            case .white:
                fillColour = CGColor(gray: 1, alpha: 1)
            case .grey:
                fillColour = PieceClipper.averageColour(of: workingImage)
            }

            for i in 0..<pieces.count {
                let piece = pieces[i]
                guard let pieceURL = piece.imagePath else { continue }

                // Load piece PNG from disk
                guard let imageSource = CGImageSourceCreateWithURL(pieceURL as CFURL, nil),
                      let pieceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    continue
                }

                // Pad to uniform square canvas
                guard let padded = PieceClipper.padToCanvas(
                    pieceImage: pieceImage,
                    canvasSize: canvasSize,
                    fillColour: fillColour
                ) else {
                    continue
                }

                // Overwrite the piece PNG
                do {
                    try PieceClipper.writePNG(padded, to: pieceURL)
                } catch {
                    return .failure(.pieceExportFailed(
                        "Piece \(piece.pieceIndex) padding: \(error.localizedDescription)"
                    ))
                }

                // Update piece dimensions
                pieces[i] = PuzzlePiece(
                    id: piece.id,
                    pieceIndex: piece.pieceIndex,
                    row: piece.row,
                    col: piece.col,
                    x1: piece.x1,
                    y1: piece.y1,
                    x2: piece.x2,
                    y2: piece.y2,
                    pieceWidth: canvasSize,
                    pieceHeight: canvasSize,
                    pieceType: piece.pieceType,
                    neighbourIDs: piece.neighbourIDs,
                    imagePath: piece.imagePath
                )

                // Report post-processing progress (0.90 to 0.94)
                let postProgress = 0.90 + 0.04 * Double(i + 1) / Double(pieces.count)
                onProgress(postProgress)
            }
        }

        // Render the lines overlay
        let linesImage = LinesRenderer.render(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            gridEdges: gridEdges,
            rows: rows,
            cols: cols,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )

        onProgress(0.95)

        // Build normalised source NSImage when AI normalisation is active
        let normalisedSource: NSImage?
        if config.pieceSize != nil {
            normalisedSource = NSImage(
                cgImage: workingImage,
                size: NSSize(width: workingImage.width, height: workingImage.height)
            )
        } else {
            normalisedSource = nil
        }

        return .success(GenerationResult(
            pieces: pieces,
            linesImage: linesImage,
            normalisedSourceImage: normalisedSource,
            outputDirectory: outputDir,
            actualPieceCount: pieces.count
        ))
    }

    // MARK: - Private Helpers

    /// Extract a CGImage from an NSImage, using the best available representation.
    private func cgImageFromNSImage(_ nsImage: NSImage) -> CGImage? {
        // Try to get the CGImage directly from representations
        if let rep = nsImage.representations.first as? NSBitmapImageRep {
            return rep.cgImage
        }

        // Fall back to rendering via TIFF
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }
}
