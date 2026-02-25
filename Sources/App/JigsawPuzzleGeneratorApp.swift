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
        .commands {
            CommandGroup(after: .newItem) {
                OpenBatchCommand()
            }
        }

        Window("Batch Process", id: "batch") {
            BatchProcessingView()
        }
        .defaultSize(width: 700, height: 600)
    }
}

/// Menu command view that opens the batch processing window.
/// Wrapped in a View so it can access @Environment(\.openWindow).
private struct OpenBatchCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Batch Process...") {
            openWindow(id: "batch")
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
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
        project.cleanupOutputDirectory()
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
            selectedPieceID = nil
        }
    }
}
