import Foundation

/// Handles persistence of Siamese models to ~/Library/Application Support/JigsawPuzzleGenerator/models/.
/// Stateless enum - all methods are static.
///
/// Disk layout:
///   models/<model-uuid>/
///     manifest.json
///     metrics.json        (optional - present after importing training results)
///     model.mlpackage/    (optional - present after importing Core ML model)
enum ModelStore {

    // MARK: - Paths

    static var modelsDirectory: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("models")
    }

    static func modelDirectory(for modelID: UUID) -> URL {
        modelsDirectory.appendingPathComponent(modelID.uuidString)
    }

    static func metricsPath(for modelID: UUID) -> URL {
        modelDirectory(for: modelID).appendingPathComponent("metrics.json")
    }

    static func coreMLModelPath(for modelID: UUID) -> URL {
        modelDirectory(for: modelID).appendingPathComponent("model.mlpackage")
    }

    // MARK: - Save

    @MainActor
    static func saveModel(_ model: SiameseModel) {
        let dir = modelDirectory(for: model.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("ModelStore: Failed to create model directory: \(error)")
            return
        }

        let manifest = ModelManifest(from: model)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = dir.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL)
        } catch {
            print("ModelStore: Failed to write manifest: \(error)")
        }

        // Save metrics separately if present
        if let metrics = model.metrics {
            saveMetrics(metrics, for: model.id)
        }
    }

    // MARK: - Metrics

    static func saveMetrics(_ metrics: TrainingMetrics, for modelID: UUID) {
        let path = metricsPath(for: modelID)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metrics)
            try data.write(to: path)
        } catch {
            print("ModelStore: Failed to write metrics: \(error)")
        }
    }

    static func loadMetrics(for modelID: UUID) -> TrainingMetrics? {
        let path = metricsPath(for: modelID)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(TrainingMetrics.self, from: data)
    }

    // MARK: - Core ML Model Import

    static func importCoreMLModel(from source: URL, for modelID: UUID) throws {
        let dest = coreMLModelPath(for: modelID)
        let fm = FileManager.default

        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
    }

    // MARK: - Load

    @MainActor
    static func loadAllModels() -> [SiameseModel] {
        let fm = FileManager.default
        let dir = modelsDirectory

        guard fm.fileExists(atPath: dir.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var models: [SiameseModel] = []

        for subdir in contents {
            let manifestURL = subdir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(ModelManifest.self, from: data) else { continue }

            let metrics = loadMetrics(for: manifest.id)
            models.append(manifest.toModel(metrics: metrics))
        }

        models.sort { $0.createdAt < $1.createdAt }
        return models
    }

    // MARK: - Delete

    static func deleteModel(id: UUID) {
        let dir = modelDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Training Report

    /// Builds a self-contained training report from a model and available datasets.
    @MainActor
    static func buildTrainingReport(model: SiameseModel, datasets: [PuzzleDataset]) -> TrainingReport {
        let dataset = datasets.first { $0.id == model.sourceDatasetID }

        let modelSection = TrainingReport.ModelSection(
            id: model.id.uuidString,
            name: model.name,
            createdAt: model.createdAt,
            status: model.status.rawValue,
            sourceDatasetID: model.sourceDatasetID.uuidString,
            sourceDatasetName: model.sourceDatasetName,
            sourcePresetName: model.sourcePresetName,
            notes: model.notes,
            trainedAt: model.trainedAt,
            scriptHash: model.scriptHash
        )

        let arch = model.architecture
        let archSection = TrainingReport.ArchitectureSection(
            convBlocks: arch.convBlocks.map { block in
                TrainingReport.ConvBlockInfo(
                    filters: block.filters,
                    kernelSize: block.kernelSize,
                    useBatchNorm: block.useBatchNorm,
                    useMaxPool: block.useMaxPool
                )
            },
            embeddingDimension: arch.embeddingDimension,
            comparisonMethod: arch.comparisonMethod.rawValue,
            dropout: arch.dropout,
            learningRate: arch.learningRate,
            batchSize: arch.batchSize,
            epochs: arch.epochs,
            inputSize: arch.inputSize,
            devicePreference: arch.devicePreference.rawValue,
            flattenedSize: arch.flattenedSize
        )

        var datasetSection: TrainingReport.DatasetSection? = nil
        if let ds = dataset {
            let cfg = ds.configuration
            var requestedCounts: [String: Int] = [:]
            for cat in DatasetCategory.allCases {
                requestedCounts[cat.rawValue] = cfg.count(for: cat)
            }

            var actualSplitCounts: [String: [String: Int]] = [:]
            for (split, catCounts) in ds.splitCounts {
                var catDict: [String: Int] = [:]
                for (cat, count) in catCounts {
                    catDict[cat.rawValue] = count
                }
                actualSplitCounts[split.rawValue] = catDict
            }

            datasetSection = TrainingReport.DatasetSection(
                id: ds.id.uuidString,
                name: ds.name,
                sourceProjectName: ds.sourceProjectName,
                rows: cfg.rows,
                columns: cfg.columns,
                pieceSize: cfg.pieceSize,
                pieceFill: cfg.pieceFill.rawValue,
                cutsPerImage: cfg.cutsPerImage,
                trainRatio: cfg.trainRatio,
                testRatio: cfg.testRatio,
                validRatio: cfg.validRatio,
                requestedCounts: requestedCounts,
                actualSplitCounts: actualSplitCounts,
                totalPairs: ds.totalPairs
            )
        }

        var resultsSection: TrainingReport.ResultsSection? = nil
        if let metrics = model.metrics {
            let epochHistory = (0..<metrics.trainLoss.count).map { i in
                TrainingReport.EpochEntry(
                    epoch: metrics.trainLoss[i].epoch,
                    trainLoss: metrics.trainLoss[i].value,
                    validLoss: i < metrics.validLoss.count ? metrics.validLoss[i].value : nil,
                    trainAccuracy: i < metrics.trainAccuracy.count ? metrics.trainAccuracy[i].value : nil,
                    validAccuracy: i < metrics.validAccuracy.count ? metrics.validAccuracy[i].value : nil
                )
            }

            resultsSection = TrainingReport.ResultsSection(
                bestEpoch: metrics.bestEpoch,
                trainingDurationSeconds: metrics.trainingDurationSeconds,
                testAccuracy: metrics.testAccuracy,
                testLoss: metrics.testLoss,
                testPrecision: metrics.testPrecision,
                testRecall: metrics.testRecall,
                testF1: metrics.testF1,
                optimalThreshold: metrics.optimalThreshold,
                confusionMatrix: metrics.confusionMatrix,
                perCategoryResults: metrics.perCategoryResults,
                epochHistory: epochHistory
            )
        }

        return TrainingReport(
            model: modelSection,
            architecture: archSection,
            dataset: datasetSection,
            results: resultsSection
        )
    }

    /// Exports a self-contained training report JSON to the given URL.
    @MainActor
    static func exportReport(model: SiameseModel, datasets: [PuzzleDataset], to url: URL) throws {
        let report = buildTrainingReport(model: model, datasets: datasets)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url)
    }
}

// MARK: - Training Report DTO

/// Self-contained training report combining model, architecture, dataset, and results.
/// Exported as training_report.json for external analysis.
struct TrainingReport: Codable {
    let model: ModelSection
    let architecture: ArchitectureSection
    let dataset: DatasetSection?
    let results: ResultsSection?

    struct ModelSection: Codable {
        let id: String
        let name: String
        let createdAt: Date
        let status: String
        let sourceDatasetID: String
        let sourceDatasetName: String
        let sourcePresetName: String?
        let notes: String
        let trainedAt: Date?
        let scriptHash: String?
    }

    struct ConvBlockInfo: Codable {
        let filters: Int
        let kernelSize: Int
        let useBatchNorm: Bool
        let useMaxPool: Bool
    }

    struct ArchitectureSection: Codable {
        let convBlocks: [ConvBlockInfo]
        let embeddingDimension: Int
        let comparisonMethod: String
        let dropout: Double
        let learningRate: Double
        let batchSize: Int
        let epochs: Int
        let inputSize: Int
        let devicePreference: String
        let flattenedSize: Int
    }

    struct DatasetSection: Codable {
        let id: String
        let name: String
        let sourceProjectName: String
        let rows: Int
        let columns: Int
        let pieceSize: Int
        let pieceFill: String
        let cutsPerImage: Int
        let trainRatio: Double
        let testRatio: Double
        let validRatio: Double
        let requestedCounts: [String: Int]
        let actualSplitCounts: [String: [String: Int]]
        let totalPairs: Int
    }

    struct EpochEntry: Codable {
        let epoch: Int
        let trainLoss: Double
        let validLoss: Double?
        let trainAccuracy: Double?
        let validAccuracy: Double?
    }

    struct ResultsSection: Codable {
        let bestEpoch: Int?
        let trainingDurationSeconds: Double?
        let testAccuracy: Double?
        let testLoss: Double?
        let testPrecision: Double?
        let testRecall: Double?
        let testF1: Double?
        let optimalThreshold: Double?
        let confusionMatrix: ConfusionMatrix?
        let perCategoryResults: [String: CategoryResult]?
        let epochHistory: [EpochEntry]
    }
}

enum ModelStoreError: Error, LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model directory not found on disk."
        }
    }
}
