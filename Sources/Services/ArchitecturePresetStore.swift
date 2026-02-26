import Foundation

/// Handles persistence of architecture presets to ~/Library/Application Support/JigsawPuzzleGenerator/presets/.
/// Stateless enum - all methods are static.
///
/// Disk layout:
///   presets/<preset-uuid>/
///     manifest.json
enum ArchitecturePresetStore {

    // MARK: - Paths

    static var presetsDirectory: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("presets")
    }

    static func presetDirectory(for presetID: UUID) -> URL {
        presetsDirectory.appendingPathComponent(presetID.uuidString)
    }

    // MARK: - Save

    @MainActor
    static func savePreset(_ preset: ArchitecturePreset) {
        let dir = presetDirectory(for: preset.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("ArchitecturePresetStore: Failed to create preset directory: \(error)")
            return
        }

        let manifest = ArchitecturePresetManifest(from: preset)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            let manifestURL = dir.appendingPathComponent("manifest.json")
            try data.write(to: manifestURL)
        } catch {
            print("ArchitecturePresetStore: Failed to write manifest: \(error)")
        }
    }

    // MARK: - Load

    @MainActor
    static func loadAllPresets() -> [ArchitecturePreset] {
        let fm = FileManager.default
        let dir = presetsDirectory

        guard fm.fileExists(atPath: dir.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var presets: [ArchitecturePreset] = []

        for subdir in contents {
            let manifestURL = subdir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            guard let data = try? Data(contentsOf: manifestURL) else { continue }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(ArchitecturePresetManifest.self, from: data) else { continue }

            presets.append(manifest.toPreset())
        }

        presets.sort { $0.createdAt < $1.createdAt }
        return presets
    }

    // MARK: - Delete

    static func deletePreset(id: UUID) {
        let dir = presetDirectory(for: id)
        try? FileManager.default.removeItem(at: dir)
    }
}
