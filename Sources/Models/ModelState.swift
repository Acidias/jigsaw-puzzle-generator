import Foundation

/// Central state for Siamese model management.
@MainActor
class ModelState: ObservableObject {
    @Published var models: [SiameseModel] = []
    @Published var selectedModelID: UUID?

    var selectedModel: SiameseModel? {
        guard let id = selectedModelID else { return nil }
        return models.first { $0.id == id }
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
