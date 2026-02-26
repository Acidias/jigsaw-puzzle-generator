import Foundation

/// Codable DTO for persisting an ArchitecturePreset to disk as manifest.json.
struct ArchitecturePresetManifest: Codable {
    let id: UUID
    var name: String
    let isBuiltIn: Bool
    let createdAt: Date
    let architecture: SiameseArchitecture

    /// Create a manifest from a runtime ArchitecturePreset.
    @MainActor
    init(from preset: ArchitecturePreset) {
        self.id = preset.id
        self.name = preset.name
        self.isBuiltIn = preset.isBuiltIn
        self.createdAt = preset.createdAt
        self.architecture = preset.architecture
    }

    /// Reconstruct a runtime ArchitecturePreset from this manifest.
    @MainActor
    func toPreset() -> ArchitecturePreset {
        ArchitecturePreset(
            id: id,
            name: name,
            architecture: architecture,
            isBuiltIn: isBuiltIn,
            createdAt: createdAt
        )
    }
}
