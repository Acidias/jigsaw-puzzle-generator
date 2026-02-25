import Foundation

/// A project is a named container grouping multiple images and their generated puzzles.
@MainActor
class PuzzleProject: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var images: [PuzzleImage] = []
    @Published var cuts: [PuzzleCut] = []
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

extension PuzzleProject: Equatable {
    nonisolated static func == (lhs: PuzzleProject, rhs: PuzzleProject) -> Bool {
        lhs.id == rhs.id
    }
}

extension PuzzleProject: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
