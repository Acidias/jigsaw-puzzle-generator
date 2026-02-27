import Foundation

/// Handles persistence of AutoML studies to ~/Library/Application Support/JigsawPuzzleGenerator/studies/.
/// Stateless enum - all methods are static.
///
/// Disk layout:
///   studies/<study-uuid>/
///     manifest.json
///     training/          (automl_train.py, requirements.txt, study.db, optuna_results.json, best_model.pth, best_metrics.json)
enum AutoMLStudyStore {

    // MARK: - Paths

    static var studiesDirectory: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("studies")
    }

    static func studyDirectory(for studyID: UUID) -> URL {
        studiesDirectory.appendingPathComponent(studyID.uuidString)
    }

    static func trainingDirectory(for studyID: UUID) -> URL {
        studyDirectory(for: studyID).appendingPathComponent("training")
    }

    // MARK: - Save

    @MainActor
    static func saveStudy(_ study: AutoMLStudy) {
        let dir = studyDirectory(for: study.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("AutoMLStudyStore: Failed to create study directory: \(error)")
            return
        }

        let manifest = AutoMLStudyManifest(from: study)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = dir.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL)
        } catch {
            print("AutoMLStudyStore: Failed to write manifest: \(error)")
        }
    }

    // MARK: - Load

    @MainActor
    static func loadAllStudies() -> [AutoMLStudy] {
        let fm = FileManager.default
        let dir = studiesDirectory

        guard fm.fileExists(atPath: dir.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var studies: [AutoMLStudy] = []

        for subdir in contents {
            let manifestURL = subdir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(AutoMLStudyManifest.self, from: data) else { continue }

            studies.append(manifest.toStudy())
        }

        studies.sort { $0.createdAt < $1.createdAt }
        return studies
    }

    // MARK: - Delete

    static func deleteStudy(id: UUID) {
        let dir = studyDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Results

    /// Load optuna_results.json from the training directory.
    static func loadResults(for studyID: UUID) -> [AutoMLTrial]? {
        let path = trainingDirectory(for: studyID).appendingPathComponent("optuna_results.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode([AutoMLTrial].self, from: data)
    }
}
