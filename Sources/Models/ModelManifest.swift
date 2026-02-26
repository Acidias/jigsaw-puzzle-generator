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
            hasImportedModel: hasImportedModel
        )
    }
}
