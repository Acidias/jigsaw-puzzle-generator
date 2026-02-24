import SwiftUI

@main
struct JigsawPuzzleGeneratorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Jigsaw Puzzle Generator") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
    }
}

/// Global application state holding all puzzle projects.
@MainActor
class AppState: ObservableObject {
    @Published var projects: [PuzzleProject] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedPieceID: UUID?

    var selectedProject: PuzzleProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var selectedPiece: PuzzlePiece? {
        guard let project = selectedProject else { return nil }
        return project.pieces.first { $0.id == selectedPieceID }
    }

    func addProject(_ project: PuzzleProject) {
        projects.append(project)
        selectedProjectID = project.id
        selectedPieceID = nil
    }

    func removeProject(_ project: PuzzleProject) {
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
            selectedPieceID = nil
        }
    }
}
