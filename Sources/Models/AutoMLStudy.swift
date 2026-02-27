import Foundation

/// Lifecycle status of an AutoML study.
enum StudyStatus: String, Codable {
    case configured
    case running
    case completed
    case cancelled
    case failed
}

/// A persisted AutoML hyperparameter search study.
/// Independent top-level entity (like PuzzleDataset, SiameseModel).
@MainActor
class AutoMLStudy: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    let sourceDatasetID: UUID
    let sourceDatasetName: String
    let sourcePresetName: String
    @Published var configuration: AutoMLConfiguration
    let createdAt: Date
    @Published var status: StudyStatus
    @Published var trials: [AutoMLTrial]
    @Published var bestTrialNumber: Int?
    @Published var bestModelID: UUID?
    @Published var completedTrials: Int
    @Published var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        sourceDatasetID: UUID,
        sourceDatasetName: String,
        sourcePresetName: String,
        configuration: AutoMLConfiguration,
        createdAt: Date = Date(),
        status: StudyStatus = .configured,
        trials: [AutoMLTrial] = [],
        bestTrialNumber: Int? = nil,
        bestModelID: UUID? = nil,
        completedTrials: Int = 0,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.sourceDatasetID = sourceDatasetID
        self.sourceDatasetName = sourceDatasetName
        self.sourcePresetName = sourcePresetName
        self.configuration = configuration
        self.createdAt = createdAt
        self.status = status
        self.trials = trials
        self.bestTrialNumber = bestTrialNumber
        self.bestModelID = bestModelID
        self.completedTrials = completedTrials
        self.notes = notes
    }
}

extension AutoMLStudy: Equatable {
    nonisolated static func == (lhs: AutoMLStudy, rhs: AutoMLStudy) -> Bool {
        lhs.id == rhs.id
    }
}

extension AutoMLStudy: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
