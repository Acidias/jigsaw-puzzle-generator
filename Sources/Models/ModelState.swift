import Foundation

/// Ephemeral training progress status (not persisted).
enum TrainingStatus: Equatable {
    case idle
    case preparingEnvironment
    case installingDependencies
    case training(epoch: Int, totalEpochs: Int)
    case importingResults
    case completed
    case failed(reason: String)
    case cancelled
}

/// Central state for Siamese model management.
@MainActor
class ModelState: ObservableObject {
    @Published var models: [SiameseModel] = []
    @Published var selectedModelID: UUID?

    // Training state
    @Published var trainingStatus: TrainingStatus = .idle
    @Published var trainingModelID: UUID?
    @Published var trainingLog: [String] = []
    @Published var liveMetrics: TrainingMetrics?
    @Published var pythonAvailable: Bool?

    var selectedModel: SiameseModel? {
        guard let id = selectedModelID else { return nil }
        return models.first { $0.id == id }
    }

    var isTraining: Bool {
        if case .idle = trainingStatus { return false }
        if case .completed = trainingStatus { return false }
        if case .failed = trainingStatus { return false }
        if case .cancelled = trainingStatus { return false }
        return true
    }

    var trainingModel: SiameseModel? {
        guard let id = trainingModelID else { return nil }
        return models.first { $0.id == id }
    }

    var trainingProgress: Double {
        if case .training(let epoch, let total) = trainingStatus, total > 0 {
            return Double(epoch) / Double(total)
        }
        return 0
    }

    func appendLog(_ line: String) {
        trainingLog.append(line)
    }

    func clearTrainingState() {
        trainingStatus = .idle
        trainingModelID = nil
        trainingLog = []
        liveMetrics = nil
    }

    func loadModels() {
        models = ModelStore.loadAllModels()
    }

    func addModel(_ model: SiameseModel) {
        models.append(model)
        ModelStore.saveModel(model)
    }

    func deleteModel(_ model: SiameseModel) {
        ModelStore.deleteModel(id: model.id)
        models.removeAll { $0.id == model.id }
        if selectedModelID == model.id {
            selectedModelID = nil
        }
    }
}
