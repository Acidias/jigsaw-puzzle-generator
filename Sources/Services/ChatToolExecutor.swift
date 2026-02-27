import AppKit
import CryptoKit
import Foundation

/// Executes chat tool calls against the app's live data.
/// Stateless enum - all methods are static.
@MainActor
enum ChatToolExecutor {

    /// Cache of the most recent Openverse search results (ordered).
    /// Populated by search_openverse, consumed by download_images.
    nonisolated(unsafe) private static var openverseCache: [OpenverseImage] = []

    static func execute(
        toolName: String,
        arguments: String,
        modelState: ModelState,
        datasetState: DatasetState,
        appState: AppState
    ) async -> (String, [ToolResultImage]) {
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

        // Data preparation tools
        case "create_project":
            guard let name = args["name"] as? String else {
                return (errorResult("Missing required parameter: name"), [])
            }
            return (createProject(name: name, appState: appState), [])
        case "search_openverse":
            guard let query = args["query"] as? String else {
                return (errorResult("Missing required parameter: query"), [])
            }
            let size = args["size"] as? String
            let category = args["category"] as? String
            let licenseType = args["license_type"] as? String
            let maxResults = args["max_results"] as? Int
            return (await searchOpenverse(query: query, size: size, category: category, licenseType: licenseType, maxResults: maxResults), [])
        case "download_images":
            guard let projectID = args["project_id"] as? String else {
                return (errorResult("Missing required parameter: project_id"), [])
            }
            let count = args["count"] as? Int
            return (await downloadImages(projectID: projectID, count: count, appState: appState), [])
        case "generate_dataset":
            guard let projectID = args["project_id"] as? String else {
                return (errorResult("Missing required parameter: project_id"), [])
            }
            return (generateDataset(projectID: projectID, args: args, appState: appState, datasetState: datasetState), [])

        // Write tools
        case "create_model":
            guard let presetID = args["preset_id"] as? String else {
                return (errorResult("Missing required parameter: preset_id"), [])
            }
            guard let datasetID = args["dataset_id"] as? String else {
                return (errorResult("Missing required parameter: dataset_id"), [])
            }
            guard let name = args["name"] as? String else {
                return (errorResult("Missing required parameter: name"), [])
            }
            let notes = args["notes"] as? String
            return (createModel(presetID: presetID, datasetID: datasetID, name: name, notes: notes, modelState: modelState, datasetState: datasetState), [])
        case "read_training_script":
            guard let modelID = args["model_id"] as? String else {
                return (errorResult("Missing required parameter: model_id"), [])
            }
            return (readTrainingScript(modelID: modelID, modelState: modelState, datasetState: datasetState), [])
        case "update_training_script":
            guard let modelID = args["model_id"] as? String else {
                return (errorResult("Missing required parameter: model_id"), [])
            }
            guard let script = args["script"] as? String else {
                return (errorResult("Missing required parameter: script"), [])
            }
            return (updateTrainingScript(modelID: modelID, script: script, modelState: modelState), [])
        case "start_training":
            guard let modelID = args["model_id"] as? String else {
                return (errorResult("Missing required parameter: model_id"), [])
            }
            return (startTraining(modelID: modelID, modelState: modelState, datasetState: datasetState), [])

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

    // MARK: - Data Preparation Tool Implementations

    private static func createProject(name: String, appState: AppState) -> String {
        let project = PuzzleProject(name: name)
        appState.addProject(project)
        appState.saveProject(project)

        return jsonString([
            "project_id": project.id.uuidString,
            "name": project.name,
            "created_at": ISO8601DateFormatter().string(from: project.createdAt),
        ])
    }

    private static func searchOpenverse(
        query: String,
        size: String?,
        category: String?,
        licenseType: String?,
        maxResults: Int?
    ) async -> String {
        var params = OpenverseSearchParams()
        params.query = query
        params.pageSize = min(maxResults ?? 20, 200)

        if let size = size {
            params.size = OpenverseSearchParams.OpenverseSize(rawValue: size)
        }
        if let category = category {
            params.category = OpenverseSearchParams.OpenverseCategory(rawValue: category)
        }
        if let licenseType = licenseType {
            params.licenseType = OpenverseSearchParams.OpenverseLicenceType(rawValue: licenseType)
        }

        do {
            let response = try await OpenverseAPI.search(params: params)

            // Cache all results for download_images to consume
            openverseCache = response.results

            // Return just a summary - the LLM doesn't need individual image details
            var result: [String: Any] = [
                "total_results_available": response.resultCount,
                "cached_for_download": response.results.count,
                "note": "Use download_images with a project_id to download these into a project.",
            ]

            // Include a few sample titles so the LLM knows what was found
            let sampleTitles = response.results.prefix(5).compactMap { $0.title }
            if !sampleTitles.isEmpty {
                result["sample_titles"] = sampleTitles
            }

            return jsonString(result)
        } catch {
            return errorResult("Openverse search failed: \(error.localizedDescription)")
        }
    }

    private static func downloadImages(
        projectID: String,
        count: Int?,
        appState: AppState
    ) async -> String {
        guard let projectUUID = UUID(uuidString: projectID),
              let project = appState.projects.first(where: { $0.id == projectUUID }) else {
            return errorResult("Project not found with ID: \(projectID)")
        }

        guard !openverseCache.isEmpty else {
            return errorResult("No cached search results. Call search_openverse first.")
        }

        let imagesToDownload = count.map { Array(openverseCache.prefix($0)) } ?? openverseCache
        var downloaded = 0
        var failed = 0

        for cachedImage in imagesToDownload {
            do {
                let (nsImage, tempURL) = try await OpenverseAPI.downloadImage(from: cachedImage.url)

                let name: String
                if let title = cachedImage.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = title
                } else {
                    name = URL(string: cachedImage.url)?.deletingPathExtension().lastPathComponent ?? "image_\(downloaded + 1)"
                }

                let puzzleImage = PuzzleImage(
                    name: name,
                    sourceImage: nsImage,
                    sourceImageURL: tempURL
                )
                puzzleImage.attribution = cachedImage.toAttribution()

                appState.addImage(puzzleImage, to: project)
                ProjectStore.copySourceImage(puzzleImage, to: project)
                appState.saveProject(project)

                downloaded += 1
            } catch {
                failed += 1
            }
        }

        return jsonString([
            "project": project.name,
            "downloaded": downloaded,
            "failed": failed,
            "total_images_in_project": project.images.count,
        ] as [String: Any])
    }

    private static func generateDataset(
        projectID: String,
        args: [String: Any],
        appState: AppState,
        datasetState: DatasetState
    ) -> String {
        guard let projectUUID = UUID(uuidString: projectID),
              let project = appState.projects.first(where: { $0.id == projectUUID }) else {
            return errorResult("Project not found with ID: \(projectID)")
        }

        guard project.images.count >= 2 else {
            return errorResult("Project '\(project.name)' has \(project.images.count) image(s). At least 2 are required for dataset generation.")
        }

        guard !datasetState.isRunning else {
            return errorResult("Dataset generation is already in progress.")
        }

        // Build configuration from args with defaults
        var config = DatasetConfiguration()
        config.projectID = project.id
        config.rows = (args["rows"] as? Int) ?? 1
        config.columns = (args["columns"] as? Int) ?? 2
        config.pieceSize = (args["piece_size"] as? Int) ?? 224
        if let fillStr = args["piece_fill"] as? String, let fill = PieceFill(rawValue: fillStr) {
            config.pieceFill = fill
        } else {
            config.pieceFill = .black
        }
        config.cutsPerImage = (args["cuts_per_image"] as? Int) ?? 10
        config.correctCount = (args["correct_count"] as? Int) ?? 500
        config.wrongShapeMatchCount = (args["wrong_shape_match_count"] as? Int) ?? 500
        config.wrongOrientationCount = (args["wrong_orientation_count"] as? Int) ?? 500
        config.wrongImageMatchCount = (args["wrong_image_match_count"] as? Int) ?? 500
        config.wrongNothingCount = (args["wrong_nothing_count"] as? Int) ?? 500

        // Parse ratios (may come as Int or Double from JSON)
        if let v = args["train_ratio"] { config.trainRatio = toDouble(v) ?? 0.70 }
        if let v = args["test_ratio"] { config.testRatio = toDouble(v) ?? 0.15 }
        if let v = args["valid_ratio"] { config.validRatio = toDouble(v) ?? 0.15 }

        // Set dataset name
        let datasetName = (args["name"] as? String)
            ?? "\(project.name) - \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))"

        datasetState.configuration = config

        // Fire off generation in a detached task
        Task.detached { @MainActor in
            await DatasetGenerator.generate(state: datasetState, project: project, name: datasetName)
        }

        return jsonString([
            "message": "Dataset generation started. Monitor progress in the Dataset Generation panel.",
            "project": project.name,
            "dataset_name": datasetName,
            "grid": "\(config.columns)x\(config.rows)",
            "piece_size": config.pieceSize,
            "total_pairs": config.totalPairs,
        ] as [String: Any])
    }

    /// Helper to parse a JSON value that may be Int or Double into a Double.
    private static func toDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Write Tool Implementations

    private static func createModel(
        presetID: String,
        datasetID: String,
        name: String,
        notes: String?,
        modelState: ModelState,
        datasetState: DatasetState
    ) -> String {
        guard let presetUUID = UUID(uuidString: presetID),
              let preset = modelState.presets.first(where: { $0.id == presetUUID }) else {
            return errorResult("Preset not found with ID: \(presetID)")
        }

        guard let datasetUUID = UUID(uuidString: datasetID),
              let dataset = datasetState.datasets.first(where: { $0.id == datasetUUID }) else {
            return errorResult("Dataset not found with ID: \(datasetID)")
        }

        // Resolve architecture (override inputSize from dataset canvas size)
        var architecture = preset.architecture
        let canvasSize = Int(ceil(Double(dataset.configuration.pieceSize) * 1.75))
        architecture.inputSize = canvasSize

        let model = SiameseModel(
            name: name,
            sourceDatasetID: dataset.id,
            sourceDatasetName: dataset.name,
            architecture: architecture,
            sourcePresetName: preset.name,
            notes: notes ?? ""
        )
        modelState.addModel(model)

        // Generate initial train.py
        let workDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        let datasetDir = DatasetStore.datasetDirectory(for: dataset.id)
        do {
            let hash = try TrainingScriptGenerator.writeTrainingFiles(
                model: model,
                datasetPath: datasetDir.path,
                to: workDir
            )
            model.scriptHash = hash
            ModelStore.saveModel(model)
        } catch {
            // Model still created, just no script yet
            print("ChatToolExecutor: Failed to write initial training files: \(error)")
        }

        let result: [String: Any] = [
            "model_id": model.id.uuidString,
            "name": model.name,
            "preset": preset.name,
            "dataset": dataset.name,
            "architecture": "\(architecture.convBlocks.count) blocks, \(architecture.embeddingDimension)-d, \(architecture.comparisonMethod.shortName)",
            "input_size": architecture.inputSize,
            "status": model.status.rawValue,
            "script_hash": model.scriptHash.map { String($0.prefix(8)) } as Any,
        ]

        return jsonString(result)
    }

    private static func readTrainingScript(
        modelID: String,
        modelState: ModelState,
        datasetState: DatasetState
    ) -> String {
        guard let uuid = UUID(uuidString: modelID),
              let model = modelState.models.first(where: { $0.id == uuid }) else {
            return errorResult("Model not found with ID: \(modelID)")
        }

        let workDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        let scriptURL = workDir.appendingPathComponent("train.py")

        // If script exists, read it
        if FileManager.default.fileExists(atPath: scriptURL.path),
           let content = try? String(contentsOf: scriptURL, encoding: .utf8) {
            return jsonString([
                "model_id": model.id.uuidString,
                "model_name": model.name,
                "script": content,
                "script_hash": model.scriptHash.map { String($0.prefix(8)) } as Any,
            ] as [String: Any])
        }

        // Generate script if missing
        let datasetDir = DatasetStore.datasetDirectory(for: model.sourceDatasetID)
        do {
            let hash = try TrainingScriptGenerator.writeTrainingFiles(
                model: model,
                datasetPath: datasetDir.path,
                to: workDir
            )
            model.scriptHash = hash
            ModelStore.saveModel(model)

            let content = try String(contentsOf: scriptURL, encoding: .utf8)
            return jsonString([
                "model_id": model.id.uuidString,
                "model_name": model.name,
                "script": content,
                "script_hash": String(hash.prefix(8)),
                "note": "Script was generated fresh (none existed on disk).",
            ] as [String: Any])
        } catch {
            return errorResult("Failed to generate training script: \(error.localizedDescription)")
        }
    }

    private static func updateTrainingScript(
        modelID: String,
        script: String,
        modelState: ModelState
    ) -> String {
        guard let uuid = UUID(uuidString: modelID),
              let model = modelState.models.first(where: { $0.id == uuid }) else {
            return errorResult("Model not found with ID: \(modelID)")
        }

        let workDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        let scriptURL = workDir.appendingPathComponent("train.py")

        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return errorResult("Failed to write train.py: \(error.localizedDescription)")
        }

        // Compute new hash
        let data = Data(script.utf8)
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        model.scriptHash = hash
        ModelStore.saveModel(model)

        return jsonString([
            "model_id": model.id.uuidString,
            "model_name": model.name,
            "script_hash": String(hash.prefix(8)),
            "message": "Training script updated successfully.",
        ])
    }

    private static func startTraining(
        modelID: String,
        modelState: ModelState,
        datasetState: DatasetState
    ) -> String {
        guard let uuid = UUID(uuidString: modelID),
              let model = modelState.models.first(where: { $0.id == uuid }) else {
            return errorResult("Model not found with ID: \(modelID)")
        }

        guard let dataset = datasetState.datasets.first(where: { $0.id == model.sourceDatasetID }) else {
            return errorResult("Dataset not found for model (ID: \(model.sourceDatasetID.uuidString))")
        }

        guard !modelState.isTraining else {
            return errorResult("Another training session is already in progress.")
        }

        guard TrainingRunner.findPython() != nil else {
            return errorResult("python3 not found. Install Python 3 to enable local training.")
        }

        // Check if a custom script exists on disk
        let workDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        let scriptURL = workDir.appendingPathComponent("train.py")
        let hasCustomScript = FileManager.default.fileExists(atPath: scriptURL.path)

        // Fire off training in a detached task (returns immediately)
        Task.detached { @MainActor in
            await TrainingRunner.train(
                model: model,
                dataset: dataset,
                state: modelState,
                skipScriptGeneration: hasCustomScript
            )
        }

        return jsonString([
            "model_id": model.id.uuidString,
            "model_name": model.name,
            "message": "Training started. Monitor progress in the model detail view.",
            "using_custom_script": hasCustomScript,
        ])
    }

    // MARK: - Vision Tool Implementations

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
            if let idx = colIndex["left_file"] { pairInfo["left_file"] = row[idx] }
            if let idx = colIndex["right_file"] { pairInfo["right_file"] = row[idx] }
            if let idx = colIndex["label"] { pairInfo["label"] = row[idx] }
            if let idx = colIndex["category"] { pairInfo["category"] = row[idx] }
            if let idx = colIndex["puzzle_id"] { pairInfo["puzzle_id"] = row[idx] }
            if let idx = colIndex["left_piece_id"] { pairInfo["left_piece_id"] = row[idx] }
            if let idx = colIndex["right_piece_id"] { pairInfo["right_piece_id"] = row[idx] }
            if let idx = colIndex["direction"] { pairInfo["direction"] = row[idx] }
            if let idx = colIndex["left_edge_index"] { pairInfo["left_edge_index"] = row[idx] }

            // Load pair images
            if let leftIdx = colIndex["left_file"] {
                let leftPath = splitDir.appendingPathComponent(row[leftIdx])
                let catName = (colIndex["category"].flatMap { row[$0] }) ?? "pair"
                let pairNum = pairs.count + 1
                if let img = loadAndEncodeImage(from: leftPath, label: "\(catName) pair \(pairNum) - left") {
                    images.append(img)
                }
            }
            if let rightIdx = colIndex["right_file"] {
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
