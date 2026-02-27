import Foundation

/// State of an individual Optuna trial.
enum TrialState: String, Codable {
    case complete
    case pruned
    case fail
}

/// Result of a single AutoML trial.
struct AutoMLTrial: Codable, Identifiable, Equatable {
    let trialNumber: Int
    let state: TrialState
    let value: Double?
    let params: [String: String]
    let duration: Double?
    let bestValidAccuracy: Double?
    let bestValidLoss: Double?

    var id: Int { trialNumber }
}
