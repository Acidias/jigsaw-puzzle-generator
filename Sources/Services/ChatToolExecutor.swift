import Foundation

/// Executes chat tool calls against the app's live data.
/// Stateless enum - all methods are static.
@MainActor
enum ChatToolExecutor {

    static func execute(
        toolName: String,
        arguments: String,
        modelState: ModelState,
        datasetState: DatasetState
    ) -> String {
        let args = parseArguments(arguments)

        switch toolName {
        case "list_models":
            return listModels(modelState: modelState)
        case "get_model_detail":
            guard let modelID = args["model_id"] as? String else {
                return errorResult("Missing required parameter: model_id")
            }
            return getModelDetail(modelID: modelID, modelState: modelState)
        case "list_datasets":
            return listDatasets(datasetState: datasetState)
        case "get_dataset_detail":
            guard let datasetID = args["dataset_id"] as? String else {
                return errorResult("Missing required parameter: dataset_id")
            }
            return getDatasetDetail(datasetID: datasetID, datasetState: datasetState)
        case "list_presets":
            return listPresets(modelState: modelState)
        case "get_preset_detail":
            guard let presetID = args["preset_id"] as? String else {
                return errorResult("Missing required parameter: preset_id")
            }
            return getPresetDetail(presetID: presetID, modelState: modelState)
        case "get_training_report":
            guard let modelID = args["model_id"] as? String else {
                return errorResult("Missing required parameter: model_id")
            }
            return getTrainingReport(modelID: modelID, modelState: modelState, datasetState: datasetState)
        case "compare_models":
            guard let modelIDs = args["model_ids"] as? [String] else {
                return errorResult("Missing required parameter: model_ids")
            }
            return compareModels(modelIDs: modelIDs, modelState: modelState)
        default:
            return errorResult("Unknown tool: \(toolName)")
        }
    }

    // MARK: - Tool Implementations

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
