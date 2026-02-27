import Foundation

/// Ephemeral AutoML progress status (not persisted).
enum AutoMLStatus: Equatable {
    case idle
    case preparingEnvironment
    case installingDependencies
    case uploadingDataset
    case running(trial: Int, totalTrials: Int)
    case downloadingResults
    case importingResults
    case completed
    case failed(reason: String)
    case cancelled
}

/// Central state for AutoML study management.
@MainActor
class AutoMLState: ObservableObject {
    @Published var studies: [AutoMLStudy] = []

    // Running state
    @Published var runningStatus: AutoMLStatus = .idle
    @Published var runningStudyID: UUID?
    @Published var runningLog: [String] = []
    @Published var liveTrials: [AutoMLTrial] = []
    @Published var liveBestValue: Double?
    @Published var liveBestTrialNumber: Int?

    // Current trial progress
    @Published var currentTrialNumber: Int = 0
    @Published var currentTrialEpoch: Int = 0
    @Published var currentTrialTotalEpochs: Int = 0
    @Published var currentTrialLiveMetrics: TrainingMetrics?

    var isRunning: Bool {
        if case .idle = runningStatus { return false }
        if case .completed = runningStatus { return false }
        if case .failed = runningStatus { return false }
        if case .cancelled = runningStatus { return false }
        return true
    }

    var runningStudy: AutoMLStudy? {
        guard let id = runningStudyID else { return nil }
        return studies.first { $0.id == id }
    }

    func appendLog(_ line: String) {
        runningLog.append(line)
    }

    func clearRunningState() {
        runningStatus = .idle
        runningStudyID = nil
        runningLog = []
        liveTrials = []
        liveBestValue = nil
        liveBestTrialNumber = nil
        currentTrialNumber = 0
        currentTrialEpoch = 0
        currentTrialTotalEpochs = 0
        currentTrialLiveMetrics = nil
    }

    /// Persist live trials to the study so partial results survive cancel/crash.
    func savePartialResults() {
        guard let study = runningStudy, !liveTrials.isEmpty else { return }
        study.trials = liveTrials
        study.completedTrials = liveTrials.filter { $0.state == .complete }.count
        if let bestNum = liveBestTrialNumber {
            study.bestTrialNumber = bestNum
        }
        AutoMLStudyStore.saveStudy(study)
    }

    // MARK: - CRUD

    func loadStudies() {
        studies = AutoMLStudyStore.loadAllStudies()
    }

    func addStudy(_ study: AutoMLStudy) {
        studies.append(study)
        AutoMLStudyStore.saveStudy(study)
    }

    func updateStudy(_ study: AutoMLStudy) {
        AutoMLStudyStore.saveStudy(study)
    }

    func deleteStudy(_ study: AutoMLStudy) {
        AutoMLStudyStore.deleteStudy(id: study.id)
        studies.removeAll { $0.id == study.id }
    }
}
