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
    @Published var selectedImageID: UUID?
    @Published var selectedCutID: UUID?
    @Published var selectedPieceID: UUID?

    var selectedProject: PuzzleProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var selectedImage: PuzzleImage? {
        guard let project = selectedProject else { return nil }
        return project.images.first { $0.id == selectedImageID }
    }

    var selectedCut: PuzzleCut? {
        guard let image = selectedImage else { return nil }
        return image.cuts.first { $0.id == selectedCutID }
    }

    var selectedPiece: PuzzlePiece? {
        guard let cut = selectedCut else { return nil }
        return cut.pieces.first { $0.id == selectedPieceID }
    }

    func addProject(_ project: PuzzleProject) {
        projects.append(project)
        selectedProjectID = project.id
        selectedImageID = nil
        selectedCutID = nil
        selectedPieceID = nil
    }

    func removeProject(_ project: PuzzleProject) {
        for image in project.images {
            for cut in image.cuts {
                cut.cleanupOutputDirectory()
            }
        }
        ProjectStore.deleteProject(id: project.id)
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id {
            selectedProjectID = projects.first?.id
            selectedImageID = nil
            selectedCutID = nil
            selectedPieceID = nil
        }
    }

    func addImage(_ image: PuzzleImage, to project: PuzzleProject) {
        project.images.append(image)
        selectedProjectID = project.id
        selectedImageID = image.id
        selectedCutID = nil
        selectedPieceID = nil
    }

    func removeImage(_ image: PuzzleImage, from project: PuzzleProject) {
        for cut in image.cuts {
            cut.cleanupOutputDirectory()
        }
        project.images.removeAll { $0.id == image.id }
        ProjectStore.deleteImage(projectID: project.id, imageID: image.id)
        if selectedImageID == image.id {
            selectedImageID = project.images.first?.id
            selectedCutID = nil
            selectedPieceID = nil
        }
    }

    /// Find the project that contains a given image ID.
    func projectForImage(id: UUID) -> PuzzleProject? {
        projects.first { project in
            project.images.contains { $0.id == id }
        }
    }

    /// Find the project and image that contain a given cut ID.
    func imageForCut(id: UUID) -> (project: PuzzleProject, image: PuzzleImage)? {
        for project in projects {
            for image in project.images {
                if image.cuts.contains(where: { $0.id == id }) {
                    return (project, image)
                }
            }
        }
        return nil
    }

    /// Find the project, image, and cut that contain a given piece ID.
    func cutForPiece(id: UUID) -> (project: PuzzleProject, image: PuzzleImage, cut: PuzzleCut)? {
        for project in projects {
            for image in project.images {
                for cut in image.cuts {
                    if cut.pieces.contains(where: { $0.id == id }) {
                        return (project, image, cut)
                    }
                }
            }
        }
        return nil
    }

    /// Load all persisted projects from disk on launch.
    func loadProjects() async {
        let loaded = ProjectStore.loadAllProjects()
        if !loaded.isEmpty {
            projects = loaded
            selectedProjectID = loaded.first?.id
            selectedImageID = loaded.first?.images.first?.id
        }
    }

    /// Save a project to disk.
    func saveProject(_ project: PuzzleProject) {
        ProjectStore.saveProject(project)
    }
}
