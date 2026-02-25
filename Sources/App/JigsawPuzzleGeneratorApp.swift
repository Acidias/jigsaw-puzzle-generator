import AppKit
import SwiftUI

@main
struct JigsawPuzzleGeneratorApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Jigsaw Puzzle Generator") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await appState.loadProjects()
                }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

/// Global application state holding all puzzle projects.
@MainActor
class AppState: ObservableObject {
    @Published var projects: [PuzzleProject] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedCutID: UUID?
    @Published var selectedCutImageID: UUID?
    @Published var selectedPieceID: UUID?

    var selectedProject: PuzzleProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var selectedCut: PuzzleCut? {
        guard let project = selectedProject else { return nil }
        return project.cuts.first { $0.id == selectedCutID }
    }

    var selectedCutImage: CutImageResult? {
        guard let cut = selectedCut else { return nil }
        return cut.imageResults.first { $0.id == selectedCutImageID }
    }

    var selectedPiece: PuzzlePiece? {
        guard let cutImage = selectedCutImage else { return nil }
        return cutImage.pieces.first { $0.id == selectedPieceID }
    }

    func addProject(_ project: PuzzleProject) {
        projects.append(project)
        selectedProjectID = project.id
        selectedCutID = nil
        selectedCutImageID = nil
        selectedPieceID = nil
    }

    func removeProject(_ project: PuzzleProject) {
        for cut in project.cuts {
            cut.cleanupOutputDirectories()
        }
        ProjectStore.deleteProject(id: project.id)
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
            selectedCutID = nil
            selectedCutImageID = nil
            selectedPieceID = nil
        }
    }

    func addImage(_ image: PuzzleImage, to project: PuzzleProject) {
        project.images.append(image)
    }

    func removeImage(_ image: PuzzleImage, from project: PuzzleProject) {
        project.images.removeAll { $0.id == image.id }
        ProjectStore.deleteImage(projectID: project.id, imageID: image.id)

        // Remove CutImageResults referencing this image from all cuts
        for cut in project.cuts {
            cut.imageResults.removeAll { $0.imageID == image.id }
        }
        // Auto-remove cuts that have no image results left
        let emptyCutIDs = project.cuts.filter { $0.imageResults.isEmpty }.map(\.id)
        for cutID in emptyCutIDs {
            ProjectStore.deleteCut(projectID: project.id, cutID: cutID)
        }
        project.cuts.removeAll { $0.imageResults.isEmpty }

        // Fix selection if needed
        if selectedCutImageID != nil, selectedCutImage == nil {
            selectedCutImageID = nil
            selectedPieceID = nil
        }
        if selectedCutID != nil, selectedCut == nil {
            selectedCutID = nil
        }
    }

    /// Find the project that contains a given cut ID.
    func projectForCut(id: UUID) -> PuzzleProject? {
        projects.first { project in
            project.cuts.contains { $0.id == id }
        }
    }

    /// Find the project and cut that contain a given CutImageResult ID.
    func cutForCutImage(id: UUID) -> (project: PuzzleProject, cut: PuzzleCut)? {
        for project in projects {
            for cut in project.cuts {
                if cut.imageResults.contains(where: { $0.id == id }) {
                    return (project, cut)
                }
            }
        }
        return nil
    }

    /// Find the project, cut, and image result that contain a given piece ID.
    func cutImageForPiece(id: UUID) -> (project: PuzzleProject, cut: PuzzleCut, imageResult: CutImageResult)? {
        for project in projects {
            for cut in project.cuts {
                for imageResult in cut.imageResults {
                    if imageResult.pieces.contains(where: { $0.id == id }) {
                        return (project, cut, imageResult)
                    }
                }
            }
        }
        return nil
    }

    /// Resolve the source PuzzleImage for a CutImageResult within a project.
    func sourceImage(for imageResult: CutImageResult, in project: PuzzleProject) -> PuzzleImage? {
        project.images.first { $0.id == imageResult.imageID }
    }

    /// Load all persisted projects from disk on launch.
    func loadProjects() async {
        let loaded = ProjectStore.loadAllProjects()
        if !loaded.isEmpty {
            projects = loaded
            selectedProjectID = loaded.first?.id
        }
    }

    /// Save a project to disk.
    func saveProject(_ project: PuzzleProject) {
        ProjectStore.saveProject(project)
    }
}
