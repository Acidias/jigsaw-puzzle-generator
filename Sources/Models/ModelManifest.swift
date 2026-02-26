import Foundation

/// Codable DTO for persisting a SiameseModel to disk as manifest.json.
struct ModelManifest: Codable {
    let id: UUID
    var name: String
    let sourceDatasetID: UUID
    let sourceDatasetName: String
    let createdAt: Date
    let status: String
    let hasImportedModel: Bool
    // Architecture
    let architecture: SiameseArchitecture
    // Experiment version control
    let sourcePresetName: String?
    let notes: String
    let trainedAt: Date?
    let scriptHash: String?

    enum CodingKeys: String, CodingKey {
        case id, name, sourceDatasetID, sourceDatasetName, createdAt, status
        case hasImportedModel, architecture
        case sourcePresetName, notes, trainedAt, scriptHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceDatasetID = try container.decode(UUID.self, forKey: .sourceDatasetID)
        sourceDatasetName = try container.decode(String.self, forKey: .sourceDatasetName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(String.self, forKey: .status)
        hasImportedModel = try container.decode(Bool.self, forKey: .hasImportedModel)
        architecture = try container.decode(SiameseArchitecture.self, forKey: .architecture)
        sourcePresetName = try container.decodeIfPresent(String.self, forKey: .sourcePresetName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        trainedAt = try container.decodeIfPresent(Date.self, forKey: .trainedAt)
        scriptHash = try container.decodeIfPresent(String.self, forKey: .scriptHash)
    }

    /// Create a manifest from a runtime SiameseModel.
    @MainActor
    init(from model: SiameseModel) {
        self.id = model.id
        self.name = model.name
        self.sourceDatasetID = model.sourceDatasetID
        self.sourceDatasetName = model.sourceDatasetName
        self.createdAt = model.createdAt
        self.status = model.status.rawValue
        self.hasImportedModel = model.hasImportedModel
        self.architecture = model.architecture
        self.sourcePresetName = model.sourcePresetName
        self.notes = model.notes
        self.trainedAt = model.trainedAt
        self.scriptHash = model.scriptHash
    }

    /// Reconstruct a runtime SiameseModel from this manifest.
    /// Metrics are loaded separately from metrics.json.
    @MainActor
    func toModel(metrics: TrainingMetrics? = nil) -> SiameseModel {
        // If status was .training when the app crashed/quit, revert to .designed
        var resolvedStatus = ModelStatus(rawValue: status) ?? .designed
        if resolvedStatus == .training {
            resolvedStatus = .designed
        }

        return SiameseModel(
            id: id,
            name: name,
            sourceDatasetID: sourceDatasetID,
            sourceDatasetName: sourceDatasetName,
            architecture: architecture,
            createdAt: createdAt,
            status: resolvedStatus,
            metrics: metrics,
            hasImportedModel: hasImportedModel,
            sourcePresetName: sourcePresetName,
            notes: notes,
            trainedAt: trainedAt,
            scriptHash: scriptHash
        )
    }
}
