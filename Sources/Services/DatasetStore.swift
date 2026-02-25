import Foundation

/// Handles persistence of datasets to ~/Library/Application Support/JigsawPuzzleGenerator/datasets/.
/// Stateless enum - all methods are static.
///
/// Disk layout:
///   datasets/<dataset-uuid>/
///     manifest.json
///     train/<category>/pair_NNNN_left.png, pair_NNNN_right.png
///     train/labels.csv
///     test/...
///     valid/...
enum DatasetStore {

    // MARK: - Paths

    static var datasetsDirectory: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("datasets")
    }

    static func datasetDirectory(for datasetID: UUID) -> URL {
        datasetsDirectory.appendingPathComponent(datasetID.uuidString)
    }

    // MARK: - Save

    @MainActor
    static func saveDataset(_ dataset: PuzzleDataset) {
        let datasetDir = datasetDirectory(for: dataset.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: datasetDir, withIntermediateDirectories: true)
        } catch {
            print("DatasetStore: Failed to create dataset directory: \(error)")
            return
        }

        let manifest = DatasetManifest(from: dataset)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = datasetDir.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL)
        } catch {
            print("DatasetStore: Failed to write manifest: \(error)")
        }
    }

    // MARK: - Load

    @MainActor
    static func loadAllDatasets() -> [PuzzleDataset] {
        let fm = FileManager.default
        let datasetsDir = datasetsDirectory

        guard fm.fileExists(atPath: datasetsDir.path) else { return [] }

        var datasets: [PuzzleDataset] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: datasetsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        for dir in contents {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(DatasetManifest.self, from: data) else { continue }

            datasets.append(manifest.toDataset())
        }

        datasets.sort { $0.createdAt < $1.createdAt }
        return datasets
    }

    // MARK: - Delete

    static func deleteDataset(id: UUID) {
        let dir = datasetDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Export

    /// Copies the dataset directory contents to an external path.
    static func exportDataset(_ dataset: PuzzleDataset, to destination: URL) throws {
        let sourceDir = datasetDirectory(for: dataset.id)
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceDir.path) else {
            throw DatasetStoreError.datasetNotFound
        }

        // Copy the entire directory contents (not the UUID folder itself)
        let contents = try fm.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for item in contents {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: destItem.path) {
                try fm.removeItem(at: destItem)
            }
            try fm.copyItem(at: item, to: destItem)
        }
    }
}

enum DatasetStoreError: Error, LocalizedError {
    case datasetNotFound

    var errorDescription: String? {
        switch self {
        case .datasetNotFound:
            return "Dataset directory not found on disk."
        }
    }
}
