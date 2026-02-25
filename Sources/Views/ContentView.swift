import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var batchState = BatchState()
    @StateObject private var openverseState = OpenverseSearchState()
    @State private var sidebarSelection: SidebarItem? = nil
    @State private var isDragTargeted = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var isBatchSelected: Bool {
        if case .batchLocal = sidebarSelection { return true }
        if case .batchOpenverse = sidebarSelection { return true }
        return false
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            VStack(spacing: 0) {
                // Detail content
                Group {
                    switch sidebarSelection {
                    case .batchLocal:
                        LocalImagesPanel(batchState: batchState)
                    case .batchOpenverse:
                        OpenversePanel(batchState: batchState, state: openverseState)
                    default:
                        projectDetailView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Batch bottom panels (only when a batch tab is selected)
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
                    importImage()
                } label: {
                    Label("Import Image", systemImage: "photo.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                if let project = appState.selectedProject, project.hasGeneratedPieces {
                    Button {
                        exportAll()
                    } label: {
                        Label("Export All", systemImage: "square.and.arrow.up")
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
        // Sync: when a project is added/selected via AppState, update sidebar selection
        .onChange(of: appState.selectedProjectID) { _, newID in
            guard let id = newID else { return }
            if let pieceID = appState.selectedPieceID {
                sidebarSelection = .piece(pieceID)
            } else {
                sidebarSelection = .project(id)
            }
        }
        .onChange(of: appState.selectedPieceID) { _, newID in
            if let id = newID {
                sidebarSelection = .piece(id)
            } else if let projectID = appState.selectedProjectID {
                sidebarSelection = .project(projectID)
            }
        }
    }

    @ViewBuilder
    private var projectDetailView: some View {
        if let project = appState.selectedProject {
            if let piece = appState.selectedPiece {
                PieceDetailView(project: project, piece: piece)
            } else {
                ImageDetailView(project: project)
            }
        } else {
            WelcomeView()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
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
        guard let image = NSImage(contentsOf: url) else {
            showError("Could not open \"\(url.lastPathComponent)\". The file may be corrupted or in an unsupported format.")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let project = PuzzleProject(name: name, sourceImage: image, sourceImageURL: url)
        appState.addProject(project)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Try loading as a file URL first
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
                        Task { @MainActor in
                            showError("Could not read the dropped file.")
                        }
                        return
                    }

                    Task { @MainActor in
                        loadImage(from: url)
                    }
                }
                return true
            }

            // Try loading as image data
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let error = error {
                        Task { @MainActor in
                            showError("Failed to read dropped image: \(error.localizedDescription)")
                        }
                        return
                    }
                    guard let data = data, let image = NSImage(data: data) else {
                        Task { @MainActor in
                            showError("The dropped image could not be decoded. It may be in an unsupported format.")
                        }
                        return
                    }
                    Task { @MainActor in
                        let project = PuzzleProject(name: "Dropped Image", sourceImage: image)
                        appState.addProject(project)
                    }
                }
                return true
            }
        }
        return false
    }

    private func exportAll() {
        guard let project = appState.selectedProject, project.hasGeneratedPieces else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export puzzle pieces"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ExportService.export(project: project, to: url)
        } catch {
            showError(error.localizedDescription)
        }
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
            Text("Import an image to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Drag and drop an image, or press Cmd+O to open")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
