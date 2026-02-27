import Foundation

/// Codable DTO for persisting an AutoMLStudy to disk as manifest.json.
struct AutoMLStudyManifest: Codable {
    let id: UUID
    var name: String
    let sourceDatasetID: UUID
    let sourceDatasetName: String
    let sourcePresetName: String
    let configuration: AutoMLConfiguration
    let createdAt: Date
    let status: String
    let trials: [AutoMLTrial]
    let bestTrialNumber: Int?
    let bestModelID: UUID?
    let completedTrials: Int
    let notes: String

    /// Create a manifest from a runtime AutoMLStudy.
    @MainActor
    init(from study: AutoMLStudy) {
        self.id = study.id
        self.name = study.name
        self.sourceDatasetID = study.sourceDatasetID
        self.sourceDatasetName = study.sourceDatasetName
        self.sourcePresetName = study.sourcePresetName
        self.configuration = study.configuration
        self.createdAt = study.createdAt
        self.status = study.status.rawValue
        self.trials = study.trials
        self.bestTrialNumber = study.bestTrialNumber
        self.bestModelID = study.bestModelID
        self.completedTrials = study.completedTrials
        self.notes = study.notes
    }

    /// Reconstruct a runtime AutoMLStudy from this manifest.
    /// Reverts .running to .configured on load (crash recovery).
    @MainActor
    func toStudy() -> AutoMLStudy {
        var resolvedStatus = StudyStatus(rawValue: status) ?? .configured
        if resolvedStatus == .running {
            resolvedStatus = .configured
        }

        return AutoMLStudy(
            id: id,
            name: name,
            sourceDatasetID: sourceDatasetID,
            sourceDatasetName: sourceDatasetName,
            sourcePresetName: sourcePresetName,
            configuration: configuration,
            createdAt: createdAt,
            status: resolvedStatus,
            trials: trials,
            bestTrialNumber: bestTrialNumber,
            bestModelID: bestModelID,
            completedTrials: completedTrials,
            notes: notes
        )
    }
}
