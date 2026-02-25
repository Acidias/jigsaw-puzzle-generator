import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var batchState = BatchState()
    @StateObject private var openverseState = OpenverseSearchState()
    @StateObject private var datasetState = DatasetState()
    @State private var sidebarSelection: SidebarItem? = nil
    @State private var isDragTargeted = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showNewProjectAlert = false
    @State private var newProjectName = ""

    private var isBatchSelected: Bool {
        if case .batchLocal = sidebarSelection { return true }
        return false
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(datasetState: datasetState, selection: $sidebarSelection)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch sidebarSelection {
                    case .batchLocal:
                        LocalImagesPanel(batchState: batchState)
                    case .batchOpenverse:
                        OpenversePanel(state: openverseState)
                    case .datasetGeneration:
                        DatasetGenerationPanel(datasetState: datasetState)
                    case .dataset(let id):
                        if let dataset = datasetState.datasets.first(where: { $0.id == id }) {
                            DatasetDetailView(dataset: dataset, datasetState: datasetState)
                        }
                    default:
                        projectDetailView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isBatchSelected {
                    Divider()

                    BatchSettingsPanel(configuration: $batchState.configuration)
                        .padding()
                        .disabled(batchState.isRunning)

                    Divider()

                    VStack(spacing: 12) {
                        if !batchState.items.isEmpty {
                            BatchProgressBar(batchState: batchState)
                        }
                        BatchControls(batchState: batchState)
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showNewProjectAlert = true
                    newProjectName = ""
                } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    importImage()
                } label: {
                    Label("Import Image", systemImage: "photo.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                if let cutImage = appState.selectedCutImage, cutImage.hasGeneratedPieces {
                    Button {
                        exportCutImage()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.05))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("New Project", isPresented: $showNewProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let project = PuzzleProject(name: name)
                appState.addProject(project)
                appState.saveProject(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new project.")
        }
        .onChange(of: appState.selectedProjectID) { _, newID in
            guard let id = newID else { return }
            if let pieceID = appState.selectedPieceID {
                sidebarSelection = .piece(pieceID)
            } else if let cutImageID = appState.selectedCutImageID {
                sidebarSelection = .cutImage(cutImageID)
            } else if let cutID = appState.selectedCutID {
                sidebarSelection = .cut(cutID)
            } else {
                sidebarSelection = .project(id)
            }
        }
        .onChange(of: appState.selectedCutID) { _, newID in
            if let id = newID {
                if let pieceID = appState.selectedPieceID {
                    sidebarSelection = .piece(pieceID)
                } else if let cutImageID = appState.selectedCutImageID {
                    sidebarSelection = .cutImage(cutImageID)
                } else {
                    sidebarSelection = .cut(id)
                }
            } else if let projectID = appState.selectedProjectID {
                sidebarSelection = .project(projectID)
            }
        }
        .onChange(of: appState.selectedCutImageID) { _, newID in
            if let id = newID {
                if let pieceID = appState.selectedPieceID {
                    sidebarSelection = .piece(pieceID)
                } else {
                    sidebarSelection = .cutImage(id)
                }
            } else if let cutID = appState.selectedCutID {
                sidebarSelection = .cut(cutID)
            }
        }
        .onChange(of: appState.selectedPieceID) { _, newID in
            if let id = newID {
                sidebarSelection = .piece(id)
            } else if let cutImageID = appState.selectedCutImageID {
                sidebarSelection = .cutImage(cutImageID)
            } else if let cutID = appState.selectedCutID {
                sidebarSelection = .cut(cutID)
            }
        }
        .task {
            datasetState.loadDatasets()
        }
    }

    @ViewBuilder
    private var projectDetailView: some View {
        if let piece = appState.selectedPiece {
            PieceDetailView(piece: piece)
        } else if let cutImage = appState.selectedCutImage,
                  let cut = appState.selectedCut,
                  let project = appState.selectedProject,
                  let source = appState.sourceImage(for: cutImage, in: project) {
            CutImageDetailView(sourceImage: source, imageResult: cutImage, configuration: cut.configuration)
        } else if let cut = appState.selectedCut, let project = appState.selectedProject {
            CutOverviewView(cut: cut, project: project)
        } else if let project = appState.selectedProject {
            ProjectDetailView(project: project)
        } else {
            WelcomeView()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func ensureProject() -> PuzzleProject {
        if let project = appState.selectedProject {
            return project
        }
        let project = PuzzleProject(name: "Imported Images")
        appState.addProject(project)
        return project
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to create a jigsaw puzzle from"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(from: url)
    }

    private func loadImage(from url: URL) {
        guard let nsImage = NSImage(contentsOf: url) else {
            showError("Could not open \"\(url.lastPathComponent)\". The file may be corrupted or in an unsupported format.")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let image = PuzzleImage(name: name, sourceImage: nsImage, sourceImageURL: url)
        let project = ensureProject()
        appState.addImage(image, to: project)
        ProjectStore.copySourceImage(image, to: project)
        appState.saveProject(project)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    if let error = error {
                        Task { @MainActor in
                            showError("Failed to read dropped file: \(error.localizedDescription)")
                        }
                        return
                    }
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else {
                        Task { @MainActor in showError("Could not read the dropped file.") }
                        return
                    }
                    Task { @MainActor in loadImage(from: url) }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let error = error {
                        Task { @MainActor in
                            showError("Failed to read dropped image: \(error.localizedDescription)")
                        }
                        return
                    }
                    guard let data = data, let nsImage = NSImage(data: data) else {
                        Task { @MainActor in
                            showError("The dropped image could not be decoded. It may be in an unsupported format.")
                        }
                        return
                    }
                    Task { @MainActor in
                        let image = PuzzleImage(name: "Dropped Image", sourceImage: nsImage)
                        let project = ensureProject()
                        appState.addImage(image, to: project)
                        appState.saveProject(project)
                    }
                }
                return true
            }
        }
        return false
    }

    private func exportCutImage() {
        guard let cutImage = appState.selectedCutImage, cutImage.hasGeneratedPieces,
              let cut = appState.selectedCut,
              let project = appState.selectedProject,
              let source = appState.sourceImage(for: cutImage, in: project) else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export puzzle pieces"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ExportService.export(
                imageResult: cutImage,
                imageName: source.name,
                imageWidth: source.imageWidth,
                imageHeight: source.imageHeight,
                attribution: source.attribution,
                configuration: cut.configuration,
                to: url
            )
        } catch {
            showError(error.localizedDescription)
        }
    }
}

/// Shows when a project is selected - source image grid + configuration panel.
struct ProjectDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var project: PuzzleProject

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if project.images.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue.opacity(0.5))
                        Text(project.name)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text("This project has no images yet")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Import an image with Cmd+O or drag and drop")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Source images grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(project.images.count) image\(project.images.count == 1 ? "" : "s")")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(project.images) { image in
                                ProjectImageCard(image: image) {
                                    appState.removeImage(image, from: project)
                                    appState.saveProject(project)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider()

                    // Generate puzzle for all images
                    ConfigurationPanel(project: project)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .navigationTitle(project.name)
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Jigsaw Puzzle Generator")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Create a project or import an image to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Press Cmd+N to create a project, or Cmd+O to import an image")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
