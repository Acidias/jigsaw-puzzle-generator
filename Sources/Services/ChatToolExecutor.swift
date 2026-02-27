import AppKit
import Foundation

/// Executes chat tool calls against the app's live data.
/// Stateless enum - all methods are static.
@MainActor
enum ChatToolExecutor {

    static func execute(
        toolName: String,
        arguments: String,
        modelState: ModelState,
        datasetState: DatasetState,
        appState: AppState
    ) -> (String, [ToolResultImage]) {
        let args = parseArguments(arguments)

        switch toolName {
        case "list_models":
            return (listModels(modelState: modelState), [])
        case "get_model_detail":
            guard let modelID = args["model_id"] as? String else {
                return (errorResult("Missing required parameter: model_id"), [])
            }
            return (getModelDetail(modelID: modelID, modelState: modelState), [])
        case "list_datasets":
            return (listDatasets(datasetState: datasetState), [])
        case "get_dataset_detail":
            guard let datasetID = args["dataset_id"] as? String else {
                return (errorResult("Missing required parameter: dataset_id"), [])
            }
            return (getDatasetDetail(datasetID: datasetID, datasetState: datasetState), [])
        case "list_presets":
            return (listPresets(modelState: modelState), [])
        case "get_preset_detail":
            guard let presetID = args["preset_id"] as? String else {
                return (errorResult("Missing required parameter: preset_id"), [])
            }
            return (getPresetDetail(presetID: presetID, modelState: modelState), [])
        case "get_training_report":
            guard let modelID = args["model_id"] as? String else {
                return (errorResult("Missing required parameter: model_id"), [])
            }
            return (getTrainingReport(modelID: modelID, modelState: modelState, datasetState: datasetState), [])
        case "compare_models":
            guard let modelIDs = args["model_ids"] as? [String] else {
                return (errorResult("Missing required parameter: model_ids"), [])
            }
            return (compareModels(modelIDs: modelIDs, modelState: modelState), [])
        case "get_sample_pairs":
            guard let datasetID = args["dataset_id"] as? String else {
                return (errorResult("Missing required parameter: dataset_id"), [])
            }
            let split = args["split"] as? String ?? "test"
            let category = args["category"] as? String
            let count = min((args["count"] as? Int) ?? 3, 5)
            return getSamplePairs(datasetID: datasetID, split: split, category: category, count: count, datasetState: datasetState)
        case "list_projects":
            return (listProjects(appState: appState), [])
        case "get_piece_images":
            guard let projectID = args["project_id"] as? String else {
                return (errorResult("Missing required parameter: project_id"), [])
            }
            guard let cutID = args["cut_id"] as? String else {
                return (errorResult("Missing required parameter: cut_id"), [])
            }
            let imageName = args["image_name"] as? String
            let count = min((args["count"] as? Int) ?? 4, 8)
            return getPieceImages(projectID: projectID, cutID: cutID, imageName: imageName, count: count, appState: appState)
        default:
            return (errorResult("Unknown tool: \(toolName)"), [])
        }
    }

    // MARK: - Image Helper

    /// Loads an image from a URL, resizes to fit within maxDim x maxDim, and returns a base64-encoded PNG.
    private static func loadAndEncodeImage(from url: URL, maxDim: Int = 512, label: String) -> ToolResultImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let originalWidth = image.size.width
        let originalHeight = image.size.height
        guard originalWidth > 0, originalHeight > 0 else { return nil }

        // Determine target size maintaining aspect ratio
        let maxDimCG = CGFloat(maxDim)
        let targetSize: NSSize
        if originalWidth <= maxDimCG && originalHeight <= maxDimCG {
            targetSize = image.size
        } else {
            let scale = min(maxDimCG / originalWidth, maxDimCG / originalHeight)
            targetSize = NSSize(width: round(originalWidth * scale), height: round(originalHeight * scale))
        }

        // Draw resized image
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()

        // Convert to PNG data
        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return ToolResultImage(
            base64Data: pngData.base64EncodedString(),
            mediaType: "image/png",
            label: label
        )
    }

    // MARK: - New Tool Implementations

    private static func getSamplePairs(
        datasetID: String,
        split: String,
        category: String?,
        count: Int,
        datasetState: DatasetState
    ) -> (String, [ToolResultImage]) {
        guard let uuid = UUID(uuidString: datasetID),
              let dataset = datasetState.datasets.first(where: { $0.id == uuid }) else {
            return (errorResult("Dataset not found with ID: \(datasetID)"), [])
        }

        let datasetDir = DatasetStore.datasetDirectory(for: uuid)
        let splitDir = datasetDir.appendingPathComponent(split)
        let labelsURL = splitDir.appendingPathComponent("labels.csv")
        let fm = FileManager.default

        guard fm.fileExists(atPath: splitDir.path) else {
            return (errorResult("Split '\(split)' not found for dataset \(dataset.name)"), [])
        }

        // Parse labels.csv to get pair metadata
        guard let labelsData = try? String(contentsOf: labelsURL, encoding: .utf8) else {
            return (errorResult("Could not read labels.csv from \(split) split"), [])
        }

        let lines = labelsData.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else {
            return (errorResult("labels.csv is empty"), [])
        }

        // Parse header to find column indices
        let header = lines[0].components(separatedBy: ",")
        let colIndex: [String: Int] = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        // Parse data rows
        var rows: [[String]] = []
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count >= header.count {
                // Apply category filter if specified
                if let cat = category,
                   let catIdx = colIndex["category"],
                   cols[catIdx] != cat {
                    continue
                }
                rows.append(cols)
            }
        }

        guard !rows.isEmpty else {
            let filterNote = category != nil ? " with category '\(category!)'" : ""
            return (errorResult("No pairs found in \(split) split\(filterNote)"), [])
        }

        // Sample up to count pairs (evenly spaced for variety)
        let sampleCount = min(count, rows.count)
        var sampledRows: [[String]] = []
        if sampleCount >= rows.count {
            sampledRows = rows
        } else {
            let step = Double(rows.count) / Double(sampleCount)
            for i in 0..<sampleCount {
                let idx = Int(Double(i) * step)
                sampledRows.append(rows[idx])
            }
        }

        var pairs: [[String: Any]] = []
        var images: [ToolResultImage] = []

        for row in sampledRows {
            var pairInfo: [String: Any] = [:]

            // Extract all available metadata columns
            if let idx = colIndex["left_image"] { pairInfo["left_image"] = row[idx] }
            if let idx = colIndex["right_image"] { pairInfo["right_image"] = row[idx] }
            if let idx = colIndex["label"] { pairInfo["label"] = row[idx] }
            if let idx = colIndex["category"] { pairInfo["category"] = row[idx] }
            if let idx = colIndex["puzzle_id"] { pairInfo["puzzle_id"] = row[idx] }
            if let idx = colIndex["left_piece_id"] { pairInfo["left_piece_id"] = row[idx] }
            if let idx = colIndex["right_piece_id"] { pairInfo["right_piece_id"] = row[idx] }
            if let idx = colIndex["direction"] { pairInfo["direction"] = row[idx] }
            if let idx = colIndex["left_edge_index"] { pairInfo["left_edge_index"] = row[idx] }

            // Load pair images
            if let leftIdx = colIndex["left_image"] {
                let leftPath = splitDir.appendingPathComponent(row[leftIdx])
                let catName = (colIndex["category"].flatMap { row[$0] }) ?? "pair"
                let pairNum = pairs.count + 1
                if let img = loadAndEncodeImage(from: leftPath, label: "\(catName) pair \(pairNum) - left") {
                    images.append(img)
                }
            }
            if let rightIdx = colIndex["right_image"] {
                let rightPath = splitDir.appendingPathComponent(row[rightIdx])
                let catName = (colIndex["category"].flatMap { row[$0] }) ?? "pair"
                let pairNum = pairs.count + 1
                if let img = loadAndEncodeImage(from: rightPath, label: "\(catName) pair \(pairNum) - right") {
                    images.append(img)
                }
            }

            pairs.append(pairInfo)
        }

        let result: [String: Any] = [
            "dataset": dataset.name,
            "split": split,
            "pairs_returned": pairs.count,
            "total_pairs_in_split": rows.count,
            "pairs": pairs,
        ]

        return (jsonString(result), images)
    }

    private static func listProjects(appState: AppState) -> [String: Any] {
        if appState.projects.isEmpty {
            return ["message": "No projects found. Create one from the sidebar."]
        }

        let summaries = appState.projects.map { project -> [String: Any] in
            var info: [String: Any] = [
                "id": project.id.uuidString,
                "name": project.name,
                "image_count": project.images.count,
                "created_at": ISO8601DateFormatter().string(from: project.createdAt),
            ]

            if !project.cuts.isEmpty {
                info["cuts"] = project.cuts.map { cut -> [String: Any] in
                    var cutInfo: [String: Any] = [
                        "id": cut.id.uuidString,
                        "grid": "\(cut.configuration.columns)x\(cut.configuration.rows)",
                        "total_pieces": cut.totalPieceCount,
                    ]
                    if !cut.imageResults.isEmpty {
                        cutInfo["images"] = cut.imageResults.map { result -> [String: Any] in
                            [
                                "image_name": result.imageName,
                                "piece_count": result.pieces.count,
                            ]
                        }
                    }
                    return cutInfo
                }
            }

            return info
        }

        return ["projects": summaries]
    }

    private static func listProjects(appState: AppState) -> String {
        let dict: [String: Any] = listProjects(appState: appState)
        return jsonString(dict)
    }

    private static func getPieceImages(
        projectID: String,
        cutID: String,
        imageName: String?,
        count: Int,
        appState: AppState
    ) -> (String, [ToolResultImage]) {
        guard let projectUUID = UUID(uuidString: projectID),
              let project = appState.projects.first(where: { $0.id == projectUUID }) else {
            return (errorResult("Project not found with ID: \(projectID)"), [])
        }

        guard let cutUUID = UUID(uuidString: cutID),
              let cut = project.cuts.first(where: { $0.id == cutUUID }) else {
            return (errorResult("Cut not found with ID: \(cutID) in project '\(project.name)'"), [])
        }

        // Find the target image result
        let imageResult: CutImageResult?
        if let name = imageName {
            imageResult = cut.imageResults.first { $0.imageName.localizedCaseInsensitiveContains(name) }
        } else {
            imageResult = cut.imageResults.first
        }

        guard let result = imageResult else {
            let filterNote = imageName != nil ? " matching '\(imageName!)'" : ""
            return (errorResult("No image results found\(filterNote) in cut \(cut.displayName)"), [])
        }

        guard !result.pieces.isEmpty else {
            return (errorResult("No pieces generated yet for '\(result.imageName)' in cut \(cut.displayName)"), [])
        }

        let cols = cut.configuration.columns

        // Sample pieces (evenly spaced for variety)
        let pieceCount = min(count, result.pieces.count)
        var sampledPieces: [PuzzlePiece] = []
        if pieceCount >= result.pieces.count {
            sampledPieces = result.pieces
        } else {
            let step = Double(result.pieces.count) / Double(pieceCount)
            for i in 0..<pieceCount {
                let idx = Int(Double(i) * step)
                sampledPieces.append(result.pieces[idx])
            }
        }

        var piecesInfo: [[String: Any]] = []
        var images: [ToolResultImage] = []

        for piece in sampledPieces {
            let gridRow = piece.pieceIndex / cols
            let gridCol = piece.pieceIndex % cols

            let info: [String: Any] = [
                "numeric_id": piece.pieceIndex,
                "grid_row": gridRow,
                "grid_col": gridCol,
                "piece_type": piece.pieceType.rawValue,
                "bounding_box": [
                    "x1": piece.x1, "y1": piece.y1,
                    "x2": piece.x2, "y2": piece.y2,
                    "width": piece.pieceWidth, "height": piece.pieceHeight,
                ] as [String: Any],
                "neighbour_ids": piece.neighbourIDs,
            ]
            piecesInfo.append(info)

            // Load piece image
            if let path = piece.imagePath,
               let img = loadAndEncodeImage(from: path, label: "Piece \(piece.pieceIndex) (\(piece.pieceType.rawValue))") {
                images.append(img)
            }
        }

        let resultJSON: [String: Any] = [
            "project": project.name,
            "cut": cut.displayName,
            "image_name": result.imageName,
            "grid": "\(cut.configuration.columns)x\(cut.configuration.rows)",
            "total_pieces": result.pieces.count,
            "pieces_returned": piecesInfo.count,
            "pieces": piecesInfo,
        ]

        return (jsonString(resultJSON), images)
    }

    // MARK: - Existing Tool Implementations

    private static func listModels(modelState: ModelState) -> String {
        if modelState.models.isEmpty {
            return jsonString(["message": "No models found. Create a model from the Model Training panel."])
        }

        let summaries = modelState.models
            .sorted { $0.createdAt > $1.createdAt }
            .map { model -> [String: Any] in
                var summary: [String: Any] = [
                    "id": model.id.uuidString,
                    "name": model.name,
                    "status": model.status.rawValue,
                    "architecture": "\(model.architecture.convBlocks.count) blocks, \(model.architecture.embeddingDimension)-d, \(model.architecture.comparisonMethod.shortName)",
                    "dataset": model.sourceDatasetName,
                ]
                if let acc = model.metrics?.testAccuracy {
                    summary["test_accuracy"] = String(format: "%.1f%%", acc * 100)
                }
                if let f1 = model.metrics?.testF1 {
                    summary["f1"] = String(format: "%.3f", f1)
                }
                if let r = model.metrics?.rankingMetrics {
                    summary["R@1"] = String(format: "%.1f%%", r.recallAt1 * 100)
                }
                if let trained = model.trainedAt {
                    summary["trained_at"] = ISO8601DateFormatter().string(from: trained)
                }
                return summary
            }

        return jsonString(["models": summaries])
    }

    private static func getModelDetail(modelID: String, modelState: ModelState) -> String {
        guard let uuid = UUID(uuidString: modelID),
              let model = modelState.models.first(where: { $0.id == uuid }) else {
            return errorResult("Model not found with ID: \(modelID)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let archData = try? encoder.encode(model.architecture),
              let archJSON = try? JSONSerialization.jsonObject(with: archData) else {
            return errorResult("Failed to encode architecture")
        }

        var detail: [String: Any] = [
            "id": model.id.uuidString,
            "name": model.name,
            "status": model.status.rawValue,
            "dataset_id": model.sourceDatasetID.uuidString,
            "dataset_name": model.sourceDatasetName,
            "created_at": ISO8601DateFormatter().string(from: model.createdAt),
            "architecture": archJSON,
        ]

        if let preset = model.sourcePresetName { detail["source_preset"] = preset }
        if !model.notes.isEmpty { detail["notes"] = model.notes }
        if let trained = model.trainedAt { detail["trained_at"] = ISO8601DateFormatter().string(from: trained) }
        if let hash = model.scriptHash { detail["script_hash"] = String(hash.prefix(8)) }

        if let metrics = model.metrics {
            var m: [String: Any] = [:]
            if let v = metrics.testAccuracy { m["test_accuracy"] = v }
            if let v = metrics.testLoss { m["test_loss"] = v }
            if let v = metrics.testPrecision { m["test_precision"] = v }
            if let v = metrics.testRecall { m["test_recall"] = v }
            if let v = metrics.testF1 { m["test_f1"] = v }
            if let v = metrics.bestEpoch { m["best_epoch"] = v }
            if let v = metrics.trainingDurationSeconds { m["duration_seconds"] = v }
            if let v = metrics.optimalThreshold { m["optimal_threshold"] = v }

            if let cm = metrics.confusionMatrix {
                m["confusion_matrix"] = [
                    "tp": cm.truePositives, "fp": cm.falsePositives,
                    "fn": cm.falseNegatives, "tn": cm.trueNegatives,
                ]
            }

            if let r = metrics.rankingMetrics {
                var rank: [String: Any] = [
                    "R@1": r.recallAt1, "R@5": r.recallAt5, "R@10": r.recallAt10,
                ]
                if let eq = r.edgeQueryCount { rank["edge_queries"] = eq }
                if let ap = r.avgPoolSize { rank["avg_pool_size"] = ap }
                m["ranking"] = rank
            }

            if let std = metrics.standardisedResults {
                m["standardised_results"] = std.map { r -> [String: Any] in
                    var entry: [String: Any] = [
                        "precision_target": "\(r.precisionTarget)%",
                        "status": r.status,
                    ]
                    if let v = r.recall { entry["recall"] = v }
                    if let v = r.f1 { entry["f1"] = v }
                    if let v = r.accuracy { entry["accuracy"] = v }
                    return entry
                }
            }

            if let fc = metrics.fourClassMetrics {
                m["four_class"] = [
                    "accuracy": fc.accuracy,
                    "per_class": fc.perClassAccuracy,
                ]
            }

            if let ri = metrics.trainingRunInfo {
                m["run_info"] = [
                    "batch_size": ri.batchSizeUsed,
                    "amp_enabled": ri.ampEnabled,
                    "input_size": ri.inputSizeUsed,
                    "pairs_per_second": ri.pairsPerSecond as Any,
                ]
            }

            detail["metrics"] = m
        }

        return jsonString(detail)
    }

    private static func listDatasets(datasetState: DatasetState) -> String {
        if datasetState.datasets.isEmpty {
            return jsonString(["message": "No datasets found. Generate one from the Dataset Generation panel."])
        }

        let summaries = datasetState.datasets.map { ds -> [String: Any] in
            [
                "id": ds.id.uuidString,
                "name": ds.name,
                "source_project": ds.sourceProjectName,
                "grid": "\(ds.configuration.rows)x\(ds.configuration.columns)",
                "piece_size": ds.configuration.pieceSize,
                "total_pairs": ds.totalPairs,
                "created_at": ISO8601DateFormatter().string(from: ds.createdAt),
            ]
        }

        return jsonString(["datasets": summaries])
    }

    private static func getDatasetDetail(datasetID: String, datasetState: DatasetState) -> String {
        guard let uuid = UUID(uuidString: datasetID),
              let ds = datasetState.datasets.first(where: { $0.id == uuid }) else {
            return errorResult("Dataset not found with ID: \(datasetID)")
        }

        let cfg = ds.configuration
        var splitInfo: [String: Any] = [:]
        for (split, catCounts) in ds.splitCounts {
            var cats: [String: Int] = [:]
            for (cat, count) in catCounts {
                cats[cat.rawValue] = count
            }
            splitInfo[split.rawValue] = cats
        }

        let detail: [String: Any] = [
            "id": ds.id.uuidString,
            "name": ds.name,
            "source_project": ds.sourceProjectName,
            "source_project_id": ds.sourceProjectID.uuidString,
            "created_at": ISO8601DateFormatter().string(from: ds.createdAt),
            "total_pairs": ds.totalPairs,
            "config": [
                "rows": cfg.rows,
                "columns": cfg.columns,
                "piece_size": cfg.pieceSize,
                "piece_fill": cfg.pieceFill.rawValue,
                "cuts_per_image": cfg.cutsPerImage,
                "requested_correct": cfg.correctCount,
                "requested_wrong_shape": cfg.wrongShapeMatchCount,
                "requested_wrong_image": cfg.wrongImageMatchCount,
                "requested_wrong_nothing": cfg.wrongNothingCount,
                "train_ratio": cfg.trainRatio,
                "test_ratio": cfg.testRatio,
                "valid_ratio": cfg.validRatio,
            ] as [String: Any],
            "split_counts": splitInfo,
        ]

        return jsonString(detail)
    }

    private static func listPresets(modelState: ModelState) -> String {
        if modelState.presets.isEmpty {
            return jsonString(["message": "No presets found."])
        }

        let summaries = modelState.presets.map { preset -> [String: Any] in
            [
                "id": preset.id.uuidString,
                "name": preset.name,
                "blocks": preset.architecture.convBlocks.count,
                "embedding_dim": preset.architecture.embeddingDimension,
                "comparison": preset.architecture.comparisonMethod.shortName,
                "epochs": preset.architecture.epochs,
                "built_in": preset.isBuiltIn,
            ]
        }

        return jsonString(["presets": summaries])
    }

    private static func getPresetDetail(presetID: String, modelState: ModelState) -> String {
        guard let uuid = UUID(uuidString: presetID),
              let preset = modelState.presets.first(where: { $0.id == uuid }) else {
            return errorResult("Preset not found with ID: \(presetID)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let archData = try? encoder.encode(preset.architecture),
              let archJSON = try? JSONSerialization.jsonObject(with: archData) else {
            return errorResult("Failed to encode architecture")
        }

        let detail: [String: Any] = [
            "id": preset.id.uuidString,
            "name": preset.name,
            "built_in": preset.isBuiltIn,
            "architecture": archJSON,
        ]

        return jsonString(detail)
    }

    private static func getTrainingReport(
        modelID: String,
        modelState: ModelState,
        datasetState: DatasetState
    ) -> String {
        guard let uuid = UUID(uuidString: modelID),
              let model = modelState.models.first(where: { $0.id == uuid }) else {
            return errorResult("Model not found with ID: \(modelID)")
        }

        var report = ModelStore.buildTrainingReport(model: model, datasets: datasetState.datasets)

        // Truncate epoch history to last 20 entries to manage token usage
        if let results = report.results, results.epochHistory.count > 20 {
            let truncated = Array(results.epochHistory.suffix(20))
            let truncatedResults = TrainingReport.ResultsSection(
                bestEpoch: results.bestEpoch,
                trainingDurationSeconds: results.trainingDurationSeconds,
                testAccuracy: results.testAccuracy,
                testLoss: results.testLoss,
                testPrecision: results.testPrecision,
                testRecall: results.testRecall,
                testF1: results.testF1,
                optimalThreshold: results.optimalThreshold,
                confusionMatrix: results.confusionMatrix,
                perCategoryResults: results.perCategoryResults,
                epochHistory: truncated,
                standardisedResults: results.standardisedResults,
                rankingMetrics: results.rankingMetrics,
                trainingRunInfo: results.trainingRunInfo,
                fourClassMetrics: results.fourClassMetrics
            )
            report = TrainingReport(
                model: report.model,
                architecture: report.architecture,
                dataset: report.dataset,
                results: truncatedResults,
                trainingScript: report.trainingScript
            )
        }

        // Truncate training script to first 100 lines
        let scriptLines = report.trainingScript.components(separatedBy: "\n")
        let truncatedScript: String
        if scriptLines.count > 100 {
            truncatedScript = scriptLines.prefix(100).joined(separator: "\n") + "\n... (truncated, \(scriptLines.count) total lines)"
        } else {
            truncatedScript = report.trainingScript
        }
        report = TrainingReport(
            model: report.model,
            architecture: report.architecture,
            dataset: report.dataset,
            results: report.results,
            trainingScript: truncatedScript
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let str = String(data: data, encoding: .utf8) else {
            return errorResult("Failed to encode training report")
        }

        return str
    }

    private static func compareModels(modelIDs: [String], modelState: ModelState) -> String {
        var comparisons: [[String: Any]] = []

        for idStr in modelIDs {
            guard let uuid = UUID(uuidString: idStr),
                  let model = modelState.models.first(where: { $0.id == uuid }) else {
                comparisons.append(["id": idStr, "error": "Not found"])
                continue
            }

            var entry: [String: Any] = [
                "id": model.id.uuidString,
                "name": model.name,
                "status": model.status.rawValue,
                "architecture": "\(model.architecture.convBlocks.count) blocks, \(model.architecture.embeddingDimension)-d, \(model.architecture.comparisonMethod.shortName)",
            ]

            if let m = model.metrics {
                if let v = m.testAccuracy { entry["test_accuracy"] = String(format: "%.1f%%", v * 100) }
                if let v = m.testF1 { entry["f1"] = String(format: "%.3f", v) }
                if let v = m.trainingDurationSeconds { entry["duration_seconds"] = Int(v) }

                if let r = m.rankingMetrics {
                    entry["R@1"] = String(format: "%.1f%%", r.recallAt1 * 100)
                }

                // R@P60 and R@P70 from standardised results
                if let std = m.standardisedResults {
                    for result in std {
                        if result.precisionTarget == 60, result.status == "achieved", let recall = result.recall {
                            entry["R@P60"] = String(format: "%.1f%%", recall * 100)
                        }
                        if result.precisionTarget == 70, result.status == "achieved", let recall = result.recall {
                            entry["R@P70"] = String(format: "%.1f%%", recall * 100)
                        }
                    }
                }
            }

            comparisons.append(entry)
        }

        return jsonString(["comparison": comparisons])
    }

    // MARK: - Helpers

    private static func parseArguments(_ json: String) -> [String: Any] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private static func errorResult(_ message: String) -> String {
        jsonString(["error": message])
    }
}
