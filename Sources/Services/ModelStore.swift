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
