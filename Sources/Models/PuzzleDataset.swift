import Foundation

/// A persisted dataset generated from a project's images.
/// Independent top-level entity - survives source project deletion.
@MainActor
class PuzzleDataset: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    let sourceProjectID: UUID
    let sourceProjectName: String
    let configuration: DatasetConfiguration
    let createdAt: Date
    /// Per-split, per-category pair counts (actual, not requested).
    let splitCounts: [DatasetSplit: [DatasetCategory: Int]]

    var totalPairs: Int {
        splitCounts.values.reduce(0) { sum, catCounts in
            sum + catCounts.values.reduce(0, +)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        sourceProjectID: UUID,
        sourceProjectName: String,
        configuration: DatasetConfiguration,
        createdAt: Date = Date(),
        splitCounts: [DatasetSplit: [DatasetCategory: Int]] = [:]
    ) {
        self.id = id
        self.name = name
        self.sourceProjectID = sourceProjectID
        self.sourceProjectName = sourceProjectName
        self.configuration = configuration
        self.createdAt = createdAt
        self.splitCounts = splitCounts
    }
}

extension PuzzleDataset: Equatable {
    nonisolated static func == (lhs: PuzzleDataset, rhs: PuzzleDataset) -> Bool {
        lhs.id == rhs.id
    }
}

extension PuzzleDataset: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
