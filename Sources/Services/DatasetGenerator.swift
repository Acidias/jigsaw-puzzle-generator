import AppKit
import Foundation

/// Errors during dataset generation.
enum DatasetError: Error, LocalizedError {
    case noProject
    case noOutputDirectory
    case insufficientImages(needed: Int, have: Int)
    case insufficientCuts(needed: Int, have: Int)
    case poolTooSmall(category: DatasetCategory, requested: Int, available: Int)
    case generationFailed(imageID: UUID, reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project selected."
        case .noOutputDirectory:
            return "No output directory selected."
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

/// Generates structured ML training datasets from 2-piece jigsaw puzzles.
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
        guard let outputDir = config.outputDirectory else {
            state.status = .failed(reason: DatasetError.noOutputDirectory.localizedDescription)
            return
        }

        // Check pool sizes
        let pools: [(DatasetCategory, Int, Int)] = [
            (.correct, config.correctCount, state.correctPool(imageCount: imageCount)),
            (.wrongShapeMatch, config.wrongShapeMatchCount, state.shapeMatchPool(imageCount: imageCount)),
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

        // Build puzzle config for 1x2 normalised grid
        var puzzleConfig = PuzzleConfiguration()
        puzzleConfig.rows = 1
        puzzleConfig.columns = 2
        puzzleConfig.pieceSize = config.pieceSize
        puzzleConfig.pieceFill = config.pieceFill
        puzzleConfig.validate()

        let cellWidth = CGFloat(config.pieceSize)
        let cellHeight = CGFloat(config.pieceSize)

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
        state.log("Phase 1: Generating pieces (\(imageCount) images x \(config.cutsPerImage) cuts)")

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
                rows: 1, cols: 2,
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

        state.log("Phase 1 complete: generated \(generationIndex * 2) pieces")

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

        // MARK: Phase 5 - Write Metadata & Cleanup (95% - 100%)

        state.status = .generating(phase: "Writing metadata...", progress: 0.95)
        state.log("Phase 5: Writing metadata and labels")

        // Write labels.csv per split
        for split in DatasetSplit.allCases {
            let pairs = allPairsBySplit[split]!
            if pairs.isEmpty { continue }
            let splitDir = outputDir.appendingPathComponent(split.rawValue)
            writeLabels(to: splitDir, split: split, pairs: pairs)
        }

        // Write metadata.json
        writeMetadata(
            to: outputDir,
            config: config,
            project: project,
            pairsBySplit: allPairsBySplit
        )

        // Cleanup temp
        cleanup(tempDir: tempDir)

        state.status = .generating(phase: "Complete", progress: 1.0)
        state.log("Dataset generation complete: \(totalWritten) pairs in \(outputDir.path)")
        state.status = .completed(pairCount: totalWritten)
    }

    // MARK: - Pair Sampling

    private static func samplePairs(
        category: DatasetCategory,
        count: Int,
        imageIDs: [UUID],
        allImageIDs: [UUID],
        cutIndices: [Int],
        pieceLookup: [UUID: [Int: [DatasetPiece]]],
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
                pairID: startPairID + pairs.count
            ) else {
                _ = attempt
                continue
            }

            // Deduplicate by image/cut combo
            let key = "\(pair.left.imageID)-\(pair.left.cutIndex)-\(pair.right.imageID)-\(pair.right.cutIndex)"
            if seen.contains(key) { continue }
            seen.insert(key)

            pairs.append(pair)
        }

        return pairs
    }

    private static func sampleOnePair(
        category: DatasetCategory,
        imageIDs: [UUID],
        allImageIDs: [UUID],
        cutIndices: [Int],
        pieceLookup: [UUID: [Int: [DatasetPiece]]],
        pairID: Int
    ) -> DatasetPair? {
        switch category {
        case .correct:
            // Random image + random cut -> piece 0 and piece 1 from same image/cut
            guard let imageID = imageIDs.randomElement(),
                  let cutIndex = cutIndices.randomElement(),
                  let pieces = pieceLookup[imageID]?[cutIndex],
                  pieces.count >= 2 else { return nil }
            let left = pieces.first { $0.pieceIndex == 0 }
            let right = pieces.first { $0.pieceIndex == 1 }
            guard let l = left, let r = right else { return nil }
            return DatasetPair(left: l, right: r, category: .correct, pairID: pairID)

        case .wrongShapeMatch:
            // Same cut (same edges) + 2 different images
            guard imageIDs.count >= 2,
                  let cutIndex = cutIndices.randomElement() else { return nil }
            let shuffled = imageIDs.shuffled()
            let imageA = shuffled[0]
            let imageB = shuffled[1]
            guard let piecesA = pieceLookup[imageA]?[cutIndex],
                  let piecesB = pieceLookup[imageB]?[cutIndex] else { return nil }
            let left = piecesA.first { $0.pieceIndex == 0 }
            let right = piecesB.first { $0.pieceIndex == 1 }
            guard let l = left, let r = right else { return nil }
            return DatasetPair(left: l, right: r, category: .wrongShapeMatch, pairID: pairID)

        case .wrongImageMatch:
            // Same image + 2 different cuts
            guard cutIndices.count >= 2,
                  let imageID = imageIDs.randomElement() else { return nil }
            let shuffledCuts = cutIndices.shuffled()
            let cutA = shuffledCuts[0]
            let cutB = shuffledCuts[1]
            guard let piecesA = pieceLookup[imageID]?[cutA],
                  let piecesB = pieceLookup[imageID]?[cutB] else { return nil }
            let left = piecesA.first { $0.pieceIndex == 0 }
            let right = piecesB.first { $0.pieceIndex == 1 }
            guard let l = left, let r = right else { return nil }
            return DatasetPair(left: l, right: r, category: .wrongImageMatch, pairID: pairID)

        case .wrongNothing:
            // 2 different images + 2 different cuts
            guard imageIDs.count >= 2, cutIndices.count >= 2 else { return nil }
            let shuffledImages = imageIDs.shuffled()
            let shuffledCuts = cutIndices.shuffled()
            let imageA = shuffledImages[0]
            let imageB = shuffledImages[1]
            let cutA = shuffledCuts[0]
            let cutB = shuffledCuts[1]
            guard let piecesA = pieceLookup[imageA]?[cutA],
                  let piecesB = pieceLookup[imageB]?[cutB] else { return nil }
            let left = piecesA.first { $0.pieceIndex == 0 }
            let right = piecesB.first { $0.pieceIndex == 1 }
            guard let l = left, let r = right else { return nil }
            return DatasetPair(left: l, right: r, category: .wrongNothing, pairID: pairID)
        }
    }

    // MARK: - Output Writing

    private static func writeLabels(to splitDir: URL, split: DatasetSplit, pairs: [DatasetPair]) {
        var csv = "pair_id,category,left_file,right_file,label\n"
        for pair in pairs {
            let leftFile = "\(pair.category.rawValue)/pair_\(String(format: "%04d", pair.pairID))_left.png"
            let rightFile = "\(pair.category.rawValue)/pair_\(String(format: "%04d", pair.pairID))_right.png"
            csv += "\(pair.pairID),\(pair.category.rawValue),\(leftFile),\(rightFile),\(pair.category.label)\n"
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
            "grid": "1x2",
            "split_ratios": [
                "train": config.trainRatio,
                "test": config.testRatio,
                "valid": config.validRatio,
            ],
            "requested_counts": [
                "correct": config.correctCount,
                "wrong_shape_match": config.wrongShapeMatchCount,
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
