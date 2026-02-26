import Foundation

/// Lifecycle status of a Siamese model.
enum ModelStatus: String, Codable {
    case designed
    case exported
    case training
    case trained
}

/// A persisted Siamese Neural Network model entity.
/// Independent top-level entity (like PuzzleDataset).
@MainActor
class SiameseModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    let sourceDatasetID: UUID
    let sourceDatasetName: String
    @Published var architecture: SiameseArchitecture
    let createdAt: Date
    @Published var status: ModelStatus
    @Published var metrics: TrainingMetrics?
    @Published var hasImportedModel: Bool
    @Published var sourcePresetName: String?
    @Published var notes: String
    @Published var trainedAt: Date?
    @Published var scriptHash: String?

    init(
        id: UUID = UUID(),
        name: String,
        sourceDatasetID: UUID,
        sourceDatasetName: String,
        architecture: SiameseArchitecture,
        createdAt: Date = Date(),
        status: ModelStatus = .designed,
        metrics: TrainingMetrics? = nil,
        hasImportedModel: Bool = false,
        sourcePresetName: String? = nil,
        notes: String = "",
        trainedAt: Date? = nil,
        scriptHash: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceDatasetID = sourceDatasetID
        self.sourceDatasetName = sourceDatasetName
        self.architecture = architecture
        self.createdAt = createdAt
        self.status = status
        self.metrics = metrics
        self.hasImportedModel = hasImportedModel
        self.sourcePresetName = sourcePresetName
        self.notes = notes
        self.trainedAt = trainedAt
        self.scriptHash = scriptHash
    }
}

extension SiameseModel: Equatable {
    nonisolated static func == (lhs: SiameseModel, rhs: SiameseModel) -> Bool {
        lhs.id == rhs.id
    }
}

extension SiameseModel: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
