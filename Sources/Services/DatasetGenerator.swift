import AppKit
import Foundation

/// Errors during dataset generation.
enum DatasetError: Error, LocalizedError {
    case noProject
    case insufficientImages(needed: Int, have: Int)
    case insufficientCuts(needed: Int, have: Int)
    case poolTooSmall(category: DatasetCategory, requested: Int, available: Int)
    case generationFailed(imageID: UUID, reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project selected."
        case .insufficientImages(let needed, let have):
            return "Need at least \(needed) images, but the project has \(have)."
        case .insufficientCuts(let needed, let have):
            return "Need at least \(needed) cuts per image, but configured \(have)."
        case .poolTooSmall(let category, let requested, let available):
            return "\(category.displayName): requested \(requested) pairs but pool size is only \(available)."
        case .generationFailed(_, let reason):
            return "Piece generation failed: \(reason)"
        case .cancelled:
            return "Generation was cancelled."
        }
    }
}

/// An adjacent pair position in the grid (two neighbouring cells).
struct AdjacentPosition {
    let r1: Int, c1: Int, r2: Int, c2: Int
}

/// Generates structured ML training datasets from jigsaw puzzles.
enum DatasetGenerator {

    // MARK: - Main Entry Point

    @MainActor
    static func generate(state: DatasetState, project: PuzzleProject) async {
        let config = state.configuration
        state.clearLog()
        state.status = .generating(phase: "Validating...", progress: 0.0)
        state.log("Starting dataset generation for project: \(project.name)")

        // Validate
        let imageCount = project.images.count
        if imageCount < 2 && config.wrongShapeMatchCount > 0 {
            state.status = .failed(reason: DatasetError.insufficientImages(needed: 2, have: imageCount).localizedDescription)
            return
        }
        if config.cutsPerImage < 2 && config.wrongImageMatchCount > 0 {
            state.status = .failed(reason: DatasetError.insufficientCuts(needed: 2, have: config.cutsPerImage).localizedDescription)
            return
        }

        // Allocate a dataset ID and output directory in internal storage
        let datasetID = UUID()
        let outputDir = DatasetStore.datasetDirectory(for: datasetID)

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            state.status = .failed(reason: "Failed to create dataset directory: \(error.localizedDescription)")
            return
        }

        // Check pool sizes
        let pools: [(DatasetCategory, Int, Int)] = [
            (.correct, config.correctCount, state.correctPool(imageCount: imageCount)),
            (.wrongShapeMatch, config.wrongShapeMatchCount, state.shapeMatchPool(imageCount: imageCount)),
            (.wrongOrientation, config.wrongOrientationCount, state.orientationPool(imageCount: imageCount)),
            (.wrongImageMatch, config.wrongImageMatchCount, state.imageMatchPool(imageCount: imageCount)),
            (.wrongNothing, config.wrongNothingCount, state.nothingPool(imageCount: imageCount)),
        ]
        for (category, requested, available) in pools {
            if requested > available {
                state.status = .failed(reason: DatasetError.poolTooSmall(
                    category: category, requested: requested, available: available
                ).localizedDescription)
                return
            }
        }

        let imageIDs = project.images.map(\.id)
        let cutIndices = Array(0..<config.cutsPerImage)

        // Build puzzle config for the configured grid
        var puzzleConfig = PuzzleConfiguration()
        puzzleConfig.rows = config.rows
        puzzleConfig.columns = config.columns
        puzzleConfig.pieceSize = config.pieceSize
        puzzleConfig.pieceFill = config.pieceFill
        puzzleConfig.validate()

        let cellWidth = CGFloat(config.pieceSize)
        let cellHeight = CGFloat(config.pieceSize)

        // Precompute all adjacent pair positions in the grid
        let adjacentPositions = buildAdjacentPositions(rows: config.rows, cols: config.columns)

        // Temp directory for all generated pieces
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dataset_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            state.status = .failed(reason: "Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        // MARK: Phase 1 - Piece Generation (0% - 70%)

        state.status = .generating(phase: "Generating pieces...", progress: 0.0)
        state.log("Phase 1: Generating pieces (\(imageCount) images x \(config.cutsPerImage) cuts, \(config.rows)x\(config.columns) grid, \(adjacentPositions.count) pair positions)")

        // Lookup: [imageID][cutIndex] -> [DatasetPiece]
        var pieceLookup: [UUID: [Int: [DatasetPiece]]] = [:]
        for id in imageIDs {
            pieceLookup[id] = [:]
        }

        let totalGenerations = imageCount * config.cutsPerImage
        var generationIndex = 0

        // Pre-generate shared edges per cut
        var sharedEdges: [Int: GridEdges] = [:]
        for cutIndex in cutIndices {
            sharedEdges[cutIndex] = GridEdges.generate(
                rows: config.rows, cols: config.columns,
                cellWidth: cellWidth, cellHeight: cellHeight
            )
        }

        for cutIndex in cutIndices {
            let gridEdges = sharedEdges[cutIndex]!

            for image in project.images {
                guard case .generating = state.status else {
                    cleanup(tempDir: tempDir)
                    return
                }

                let imageID = image.id

                // Create output directory for this cut/image
                let pieceDir = tempDir
                    .appendingPathComponent("cut_\(cutIndex)")
                    .appendingPathComponent(imageID.uuidString)
                try? FileManager.default.createDirectory(at: pieceDir, withIntermediateDirectories: true)

                let generator = PuzzleGenerator()
                let result = await generator.generate(
                    image: image.sourceImage,
                    imageURL: image.sourceImageURL,
                    configuration: puzzleConfig,
                    gridEdges: gridEdges,
                    onProgress: { _ in }
                )

                switch result {
                case .success(let genResult):
                    var pieces: [DatasetPiece] = []
                    let cols = config.columns
                    for piece in genResult.pieces {
                        guard let sourcePath = piece.imagePath else { continue }
                        let destPath = pieceDir.appendingPathComponent("piece_\(piece.pieceIndex).png")
                        do {
                            if FileManager.default.fileExists(atPath: destPath.path) {
                                try FileManager.default.removeItem(at: destPath)
                            }
                            try FileManager.default.moveItem(at: sourcePath, to: destPath)
                        } catch {
                            try? FileManager.default.copyItem(at: sourcePath, to: destPath)
                        }
                        pieces.append(DatasetPiece(
                            imageID: imageID,
                            cutIndex: cutIndex,
                            pieceIndex: piece.pieceIndex,
                            gridRow: piece.pieceIndex / cols,
                            gridCol: piece.pieceIndex % cols,
                            pngPath: destPath
                        ))
                    }
                    pieceLookup[imageID]?[cutIndex] = pieces

                    // Clean up the generation output directory
                    try? FileManager.default.removeItem(at: genResult.outputDirectory)

                case .failure(let error):
                    state.status = .failed(reason: DatasetError.generationFailed(
                        imageID: imageID,
                        reason: error.localizedDescription
                    ).localizedDescription)
                    cleanup(tempDir: tempDir)
                    return
                }

                generationIndex += 1
                let progress = 0.70 * Double(generationIndex) / Double(totalGenerations)
                state.status = .generating(
                    phase: "Generating pieces (\(generationIndex)/\(totalGenerations))...",
                    progress: progress
                )
            }
        }

        let piecesPerGeneration = config.rows * config.columns
        state.log("Phase 1 complete: generated \(generationIndex * piecesPerGeneration) pieces")

        // MARK: Phase 2 - Build Index (70% - 75%)

        state.status = .generating(phase: "Building index...", progress: 0.70)
        state.log("Phase 2: Building piece index")

        // Index is already built as pieceLookup

        state.status = .generating(phase: "Index built", progress: 0.75)

        // MARK: Phase 3 - Split Source Images (75%)

        state.status = .generating(phase: "Splitting images...", progress: 0.75)
        state.log("Phase 3: Splitting images into train/test/valid")

        var shuffledIDs = imageIDs
        shuffledIDs.shuffle()

        let trainEnd = Int(round(Double(imageCount) * config.trainRatio))
        let testEnd = trainEnd + Int(round(Double(imageCount) * config.testRatio))

        let splitAssignment: [DatasetSplit: [UUID]] = [
            .train: Array(shuffledIDs[0..<trainEnd]),
            .test: Array(shuffledIDs[trainEnd..<min(testEnd, imageCount)]),
            .valid: Array(shuffledIDs[min(testEnd, imageCount)..<imageCount]),
        ]

        for split in DatasetSplit.allCases {
            state.log("  \(split.rawValue): \(splitAssignment[split]!.count) images")
        }

        // MARK: Phase 4 - Sample & Write Pairs (75% - 95%)

        state.status = .generating(phase: "Sampling pairs...", progress: 0.75)
        state.log("Phase 4: Sampling and writing pairs")

        // Create output directory structure
        do {
            for split in DatasetSplit.allCases {
                for category in DatasetCategory.allCases {
                    let dir = outputDir
                        .appendingPathComponent(split.rawValue)
                        .appendingPathComponent(category.rawValue)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
            }
        } catch {
            state.status = .failed(reason: "Failed to create output directories: \(error.localizedDescription)")
            cleanup(tempDir: tempDir)
            return
        }

        var allPairsBySplit: [DatasetSplit: [DatasetPair]] = [
            .train: [], .test: [], .valid: [],
        ]
        var globalPairID = 0

        let totalCategories = DatasetCategory.allCases.count * DatasetSplit.allCases.count
        var categoryProgress = 0

        for category in DatasetCategory.allCases {
            let totalCount = config.count(for: category)

            for split in DatasetSplit.allCases {
                guard case .generating = state.status else {
                    cleanup(tempDir: tempDir)
                    return
                }

                let splitImageIDs = splitAssignment[split]!
                let splitRatio = config.ratio(for: split)
                let count = Int(floor(Double(totalCount) * splitRatio))

                if count == 0 || splitImageIDs.isEmpty {
                    categoryProgress += 1
                    continue
                }

                let pairs = samplePairs(
                    category: category,
                    count: count,
                    imageIDs: splitImageIDs,
                    allImageIDs: imageIDs,
                    cutIndices: cutIndices,
                    pieceLookup: pieceLookup,
                    adjacentPositions: adjacentPositions,
                    startPairID: globalPairID
                )

                // Copy PNGs to output
                let splitDir = outputDir.appendingPathComponent(split.rawValue)
                for pair in pairs {
                    let catDir = splitDir.appendingPathComponent(pair.category.rawValue)
                    let leftDest = catDir.appendingPathComponent("pair_\(String(format: "%04d", pair.pairID))_left.png")
                    let rightDest = catDir.appendingPathComponent("pair_\(String(format: "%04d", pair.pairID))_right.png")

                    try? FileManager.default.copyItem(at: pair.left.pngPath, to: leftDest)
                    try? FileManager.default.copyItem(at: pair.right.pngPath, to: rightDest)
                }

                allPairsBySplit[split]!.append(contentsOf: pairs)
                globalPairID += pairs.count

                categoryProgress += 1
                let progress = 0.75 + 0.20 * Double(categoryProgress) / Double(totalCategories)
                state.status = .generating(
                    phase: "Writing \(category.displayName) pairs (\(split.rawValue))...",
                    progress: progress
                )
                state.log("  \(split.rawValue)/\(category.rawValue): \(pairs.count) pairs")
            }
        }

        let totalWritten = allPairsBySplit.values.reduce(0) { $0 + $1.count }
        state.log("Phase 4 complete: \(totalWritten) total pairs written")

        // MARK: Phase 5 - Persist Dataset & Cleanup (95% - 100%)

        state.status = .generating(phase: "Writing metadata...", progress: 0.95)
        state.log("Phase 5: Writing metadata, labels, and persisting dataset")

        // Write labels.csv per split
        for split in DatasetSplit.allCases {
            let pairs = allPairsBySplit[split]!
            if pairs.isEmpty { continue }
            let splitDir = outputDir.appendingPathComponent(split.rawValue)
            writeLabels(to: splitDir, split: split, pairs: pairs)
        }

        // Write metadata.json (for external consumption when exported)
        writeMetadata(
            to: outputDir,
            config: config,
            project: project,
            pairsBySplit: allPairsBySplit
        )

        // Build split counts for the dataset object
        var splitCounts: [DatasetSplit: [DatasetCategory: Int]] = [:]
        for split in DatasetSplit.allCases {
            let pairs = allPairsBySplit[split] ?? []
            var catCounts: [DatasetCategory: Int] = [:]
            for category in DatasetCategory.allCases {
                catCounts[category] = pairs.filter { $0.category == category }.count
            }
            splitCounts[split] = catCounts
        }

        // Create and persist the dataset
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let datasetName = "\(project.name) - \(dateFormatter.string(from: Date()))"

        let dataset = PuzzleDataset(
            id: datasetID,
            name: datasetName,
            sourceProjectID: project.id,
            sourceProjectName: project.name,
            configuration: config,
            splitCounts: splitCounts
        )
        DatasetStore.saveDataset(dataset)
        state.datasets.append(dataset)

        // Cleanup temp
        cleanup(tempDir: tempDir)

        state.status = .generating(phase: "Complete", progress: 1.0)
        state.log("Dataset generation complete: \(totalWritten) pairs persisted as \"\(datasetName)\"")
        state.status = .completed(pairCount: totalWritten)
    }

    // MARK: - Adjacent Position Helpers

    /// Build all adjacent pair positions (horizontal + vertical) in a grid.
    private static func buildAdjacentPositions(rows: Int, cols: Int) -> [AdjacentPosition] {
        var positions: [AdjacentPosition] = []
        // Horizontal neighbours
        for r in 0..<rows {
            for c in 0..<(cols - 1) {
                positions.append(AdjacentPosition(r1: r, c1: c, r2: r, c2: c + 1))
            }
        }
        // Vertical neighbours
        for r in 0..<(rows - 1) {
            for c in 0..<cols {
                positions.append(AdjacentPosition(r1: r, c1: c, r2: r + 1, c2: c))
            }
        }
        return positions
    }

    /// Find a piece at a given grid coordinate within a pieces array.
    private static func piece(atRow row: Int, col: Int, in pieces: [DatasetPiece]) -> DatasetPiece? {
        pieces.first { $0.gridRow == row && $0.gridCol == col }
    }

    // MARK: - Pair Sampling

    private static func samplePairs(
        category: DatasetCategory,
        count: Int,
        imageIDs: [UUID],
        allImageIDs: [UUID],
        cutIndices: [Int],
        pieceLookup: [UUID: [Int: [DatasetPiece]]],
        adjacentPositions: [AdjacentPosition],
        startPairID: Int
    ) -> [DatasetPair] {
        var pairs: [DatasetPair] = []
        var seen = Set<String>()
        let maxRetries = count * 10

        for attempt in 0..<maxRetries {
            if pairs.count >= count { break }
            guard let pair = sampleOnePair(
                category: category,
                imageIDs: imageIDs,
                allImageIDs: allImageIDs,
                cutIndices: cutIndices,
                pieceLookup: pieceLookup,
                adjacentPositions: adjacentPositions,
                pairID: startPairID + pairs.count
            ) else {
                _ = attempt
                continue
            }

            // Deduplicate by image/cut/position combo
            let key = "\(pair.left.imageID)-\(pair.left.cutIndex)-\(pair.left.gridRow),\(pair.left.gridCol)"
                + "-\(pair.right.imageID)-\(pair.right.cutIndex)-\(pair.right.gridRow),\(pair.right.gridCol)"
            if seen.contains(key) { continue }
            seen.insert(key)

            pairs.append(pair)
        }

        return pairs
    }

    /// Derive direction and left-piece edge index from an adjacent position.
    /// Horizontal neighbour (same row): direction "R", left piece's right edge (index 1).
    /// Vertical neighbour (same col): direction "D", left piece's bottom edge (index 2).
    private static func edgeInfo(for pos: AdjacentPosition) -> (direction: String, leftEdgeIndex: Int) {
        if pos.r1 == pos.r2 {
            return ("R", 1)  // horizontal: left piece's right edge
        } else {
            return ("D", 2)  // vertical: left piece's bottom edge
        }
    }

    private static func sampleOnePair(
        category: DatasetCategory,
        imageIDs: [UUID],
        allImageIDs: [UUID],
        cutIndices: [Int],
        pieceLookup: [UUID: [Int: [DatasetPiece]]],
        adjacentPositions: [AdjacentPosition],
        pairID: Int
    ) -> DatasetPair? {
        guard let pos = adjacentPositions.randomElement() else { return nil }
        let (direction, leftEdgeIndex) = edgeInfo(for: pos)

        switch category {
        case .correct:
            // Same image, same cut, adjacent pair at random position
            guard let imageID = imageIDs.randomElement(),
                  let cutIndex = cutIndices.randomElement(),
                  let pieces = pieceLookup[imageID]?[cutIndex],
                  let left = piece(atRow: pos.r1, col: pos.c1, in: pieces),
                  let right = piece(atRow: pos.r2, col: pos.c2, in: pieces) else { return nil }
            return DatasetPair(left: left, right: right, category: .correct, pairID: pairID,
                               direction: direction, leftEdgeIndex: leftEdgeIndex)

        case .wrongOrientation:
            // Same image, same cut, adjacent pair - but swap left and right
            guard let imageID = imageIDs.randomElement(),
                  let cutIndex = cutIndices.randomElement(),
                  let pieces = pieceLookup[imageID]?[cutIndex],
                  let left = piece(atRow: pos.r1, col: pos.c1, in: pieces),
                  let right = piece(atRow: pos.r2, col: pos.c2, in: pieces) else { return nil }
            // Swap: right becomes left, left becomes right
            return DatasetPair(left: right, right: left, category: .wrongOrientation, pairID: pairID,
                               direction: direction, leftEdgeIndex: leftEdgeIndex)

        case .wrongShapeMatch:
            // Same cut (shared GridEdges), same pair position, different images
            guard imageIDs.count >= 2,
                  let cutIndex = cutIndices.randomElement() else { return nil }
            let shuffled = imageIDs.shuffled()
            let imageA = shuffled[0]
            let imageB = shuffled[1]
            guard let piecesA = pieceLookup[imageA]?[cutIndex],
                  let piecesB = pieceLookup[imageB]?[cutIndex],
                  let left = piece(atRow: pos.r1, col: pos.c1, in: piecesA),
                  let right = piece(atRow: pos.r2, col: pos.c2, in: piecesB) else { return nil }
            return DatasetPair(left: left, right: right, category: .wrongShapeMatch, pairID: pairID,
                               direction: direction, leftEdgeIndex: leftEdgeIndex)

        case .wrongImageMatch:
            // Same image, same pair position, different cuts
            guard cutIndices.count >= 2,
                  let imageID = imageIDs.randomElement() else { return nil }
            let shuffledCuts = cutIndices.shuffled()
            let cutA = shuffledCuts[0]
            let cutB = shuffledCuts[1]
            guard let piecesA = pieceLookup[imageID]?[cutA],
                  let piecesB = pieceLookup[imageID]?[cutB],
                  let left = piece(atRow: pos.r1, col: pos.c1, in: piecesA),
                  let right = piece(atRow: pos.r2, col: pos.c2, in: piecesB) else { return nil }
            return DatasetPair(left: left, right: right, category: .wrongImageMatch, pairID: pairID,
                               direction: direction, leftEdgeIndex: leftEdgeIndex)

        case .wrongNothing:
            // Different images, different cuts, random pair position
            guard imageIDs.count >= 2, cutIndices.count >= 2 else { return nil }
            let shuffledImages = imageIDs.shuffled()
            let shuffledCuts = cutIndices.shuffled()
            let imageA = shuffledImages[0]
            let imageB = shuffledImages[1]
            let cutA = shuffledCuts[0]
            let cutB = shuffledCuts[1]
            guard let piecesA = pieceLookup[imageA]?[cutA],
                  let piecesB = pieceLookup[imageB]?[cutB],
                  let left = piece(atRow: pos.r1, col: pos.c1, in: piecesA),
                  let right = piece(atRow: pos.r2, col: pos.c2, in: piecesB) else { return nil }
            return DatasetPair(left: left, right: right, category: .wrongNothing, pairID: pairID,
                               direction: direction, leftEdgeIndex: leftEdgeIndex)
        }
    }

    // MARK: - Output Writing

    private static func writeLabels(to splitDir: URL, split: DatasetSplit, pairs: [DatasetPair]) {
        var csv = "pair_id,category,left_file,right_file,label,puzzle_id,left_piece_id,right_piece_id,direction,left_edge_index\n"
        for pair in pairs {
            let leftFile = "\(pair.category.rawValue)/pair_\(String(format: "%04d", pair.pairID))_left.png"
            let rightFile = "\(pair.category.rawValue)/pair_\(String(format: "%04d", pair.pairID))_right.png"
            let puzzleID = "\(pair.left.imageID.uuidString)-\(pair.left.cutIndex)"
            let leftPieceID = "\(pair.left.gridRow)_\(pair.left.gridCol)"
            let rightPieceID = "\(pair.right.gridRow)_\(pair.right.gridCol)"
            csv += "\(pair.pairID),\(pair.category.rawValue),\(leftFile),\(rightFile),\(pair.category.label),"
            csv += "\(puzzleID),\(leftPieceID),\(rightPieceID),\(pair.direction),\(pair.leftEdgeIndex)\n"
        }
        let labelsURL = splitDir.appendingPathComponent("labels.csv")
        try? csv.write(to: labelsURL, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func writeMetadata(
        to outputDir: URL,
        config: DatasetConfiguration,
        project: PuzzleProject,
        pairsBySplit: [DatasetSplit: [DatasetPair]]
    ) {
        var splitCounts: [String: [String: Int]] = [:]
        for split in DatasetSplit.allCases {
            let pairs = pairsBySplit[split] ?? []
            var catCounts: [String: Int] = [:]
            for category in DatasetCategory.allCases {
                catCounts[category.rawValue] = pairs.filter { $0.category == category }.count
            }
            catCounts["total"] = pairs.count
            splitCounts[split.rawValue] = catCounts
        }

        let totalPairs = pairsBySplit.values.reduce(0) { $0 + $1.count }
        let canvasSize = Int(ceil(Double(config.pieceSize) * 1.75))

        let metadata: [String: Any] = [
            "version": 1,
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "project_name": project.name,
            "image_count": project.images.count,
            "cuts_per_image": config.cutsPerImage,
            "piece_size": config.pieceSize,
            "canvas_size": canvasSize,
            "piece_fill": config.pieceFill.rawValue,
            "grid": "\(config.rows)x\(config.columns)",
            "split_ratios": [
                "train": config.trainRatio,
                "test": config.testRatio,
                "valid": config.validRatio,
            ],
            "requested_counts": [
                "correct": config.correctCount,
                "wrong_shape_match": config.wrongShapeMatchCount,
                "wrong_orientation": config.wrongOrientationCount,
                "wrong_image_match": config.wrongImageMatchCount,
                "wrong_nothing": config.wrongNothingCount,
            ],
            "actual_counts": splitCounts,
            "total_pairs": totalPairs,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            let metadataURL = outputDir.appendingPathComponent("metadata.json")
            try? jsonData.write(to: metadataURL)
        }
    }

    // MARK: - Cleanup

    private static func cleanup(tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }
}
