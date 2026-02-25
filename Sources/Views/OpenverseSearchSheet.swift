import SwiftUI

// MARK: - Search State

@MainActor
class OpenverseSearchState: ObservableObject {
    @Published var params = OpenverseSearchParams()
    @Published var results: [OpenverseImage] = []
    @Published var selectedImageIDs: Set<String> = []
    @Published var isSearching = false
    @Published var isDownloading = false
    @Published var downloadCompleted = 0
    @Published var downloadTotal = 0
    @Published var errorMessage: String?
    @Published var totalResultCount = 0
    @Published var pageCount = 0
    @Published var downloadFailures: [String] = []
    @Published var thumbnailCache: [String: NSImage] = [:]

    func search() {
        guard !params.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        params.page = 1
        results = []
        selectedImageIDs = []
        thumbnailCache = [:]
        downloadFailures = []

        Task {
            do {
                let response = try await OpenverseAPI.search(params: params)
                results = response.results
                totalResultCount = response.resultCount
                pageCount = response.pageCount
                loadThumbnails(for: response.results)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func loadNextPage() {
        guard params.page < pageCount, !isSearching else { return }
        isSearching = true
        params.page += 1

        Task {
            do {
                let response = try await OpenverseAPI.search(params: params)
                results.append(contentsOf: response.results)
                loadThumbnails(for: response.results)
            } catch {
                errorMessage = error.localizedDescription
                params.page -= 1
            }
            isSearching = false
        }
    }

    /// Downloads selected images and adds them directly to a project as PuzzleImages.
    func downloadSelected(into project: PuzzleProject, appState: AppState) {
        let selected = results.filter { selectedImageIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isDownloading = true
        downloadCompleted = 0
        downloadTotal = selected.count
        downloadFailures = []

        Task {
            for image in selected {
                do {
                    let (nsImage, tempURL) = try await OpenverseAPI.downloadImage(from: image.url)
                    let name = image.title?.trimmingCharacters(in: .whitespaces).isEmpty == false
                        ? image.title!
                        : "openverse_\(image.id)"

                    let puzzleImage = PuzzleImage(
                        name: name,
                        sourceImage: nsImage,
                        sourceImageURL: tempURL
                    )
                    puzzleImage.attribution = image.toAttribution()

                    appState.addImage(puzzleImage, to: project)
                    ProjectStore.copySourceImage(puzzleImage, to: project)
                    appState.saveProject(project)
                } catch {
                    let name = image.title ?? image.id
                    downloadFailures.append(name)
                }
                downloadCompleted += 1
            }
            isDownloading = false
            selectedImageIDs = []
        }
    }

    func toggleSelection(_ id: String) {
        if selectedImageIDs.contains(id) {
            selectedImageIDs.remove(id)
        } else {
            selectedImageIDs.insert(id)
        }
    }

    func selectAll() {
        selectedImageIDs = Set(results.map(\.id))
    }

    private func loadThumbnails(for images: [OpenverseImage]) {
        for image in images {
            guard let thumbURL = image.thumbnail else { continue }
            Task {
                guard let url = URL(string: thumbURL) else { return }
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let nsImage = NSImage(data: data) {
                    thumbnailCache[image.id] = nsImage
                }
            }
        }
    }
}

// MARK: - Openverse Panel

struct OpenversePanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var state: OpenverseSearchState

    @State private var showProjectPicker = false
    @State private var pickerProjectID: UUID?
    @State private var pickerNewName = ""
    @State private var pickerMode: ProjectPickerMode = .existing

    fileprivate enum ProjectPickerMode {
        case existing
        case createNew
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                TextField("Search Openverse...", text: $state.params.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.search() }

                Button("Search") {
                    state.search()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.params.query.trimmingCharacters(in: .whitespaces).isEmpty || state.isSearching)
            }
            .padding()

            // Filters
            HStack(spacing: 16) {
                Picker("Size:", selection: $state.params.size) {
                    Text("Any").tag(OpenverseSearchParams.OpenverseSize?.none)
                    ForEach(OpenverseSearchParams.OpenverseSize.allCases) { size in
                        Text(size.displayName).tag(Optional(size))
                    }
                }
                .frame(width: 160)

                Picker("Category:", selection: $state.params.category) {
                    Text("Any").tag(OpenverseSearchParams.OpenverseCategory?.none)
                    ForEach(OpenverseSearchParams.OpenverseCategory.allCases) { cat in
                        Text(cat.displayName).tag(Optional(cat))
                    }
                }
                .frame(width: 200)

                Picker("Max results:", selection: $state.params.pageSize) {
                    Text("20").tag(20)
                    Text("40").tag(40)
                    Text("80").tag(80)
                    Text("200").tag(200)
                    Text("500").tag(500)
                }
                .frame(width: 180)

                Spacer()

                if state.totalResultCount > 0 {
                    Text("\(state.totalResultCount) results found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Results area
            if state.isSearching && state.results.isEmpty {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if state.results.isEmpty && state.totalResultCount == 0 && !state.isSearching {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    if state.errorMessage == nil {
                        Text(state.params.query.isEmpty ? "Enter a search term above" : "No results found")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(state.results) { image in
                            OpenverseResultCard(
                                image: image,
                                isSelected: state.selectedImageIDs.contains(image.id),
                                thumbnail: state.thumbnailCache[image.id]
                            )
                            .onTapGesture {
                                state.toggleSelection(image.id)
                            }
                        }
                    }
                    .padding()

                    // Load more button
                    if state.params.page < state.pageCount {
                        Button {
                            state.loadNextPage()
                        } label: {
                            if state.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Load More Results")
                            }
                        }
                        .disabled(state.isSearching)
                        .padding(.bottom)
                    }
                }
            }

            Divider()

            // Error message
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // Download failures
            if !state.downloadFailures.isEmpty {
                Text("Failed to download: \(state.downloadFailures.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            // Bottom bar
            HStack {
                if !state.results.isEmpty {
                    Text("\(state.selectedImageIDs.count) image\(state.selectedImageIDs.count == 1 ? "" : "s") selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Select All") {
                        state.selectAll()
                    }
                    .controlSize(.small)
                    .disabled(state.selectedImageIDs.count == state.results.count)
                }

                Spacer()

                if state.isDownloading {
                    ProgressView(
                        value: Double(state.downloadCompleted),
                        total: Double(state.downloadTotal)
                    )
                    .frame(width: 100)
                    Text("Downloading \(state.downloadCompleted)/\(state.downloadTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Add to Project...") {
                    prepareProjectPicker()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.selectedImageIDs.isEmpty || state.isDownloading)
            }
            .padding()
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                projects: appState.projects,
                pickerMode: $pickerMode,
                selectedProjectID: $pickerProjectID,
                newProjectName: $pickerNewName,
                imageCount: state.selectedImageIDs.count,
                onAdd: { project in
                    state.downloadSelected(into: project, appState: appState)
                }
            )
            .environmentObject(appState)
        }
    }

    private func prepareProjectPicker() {
        if appState.projects.isEmpty {
            pickerMode = .createNew
            pickerNewName = state.params.query.trimmingCharacters(in: .whitespaces)
        } else {
            pickerMode = .existing
            pickerProjectID = appState.selectedProject?.id ?? appState.projects.first?.id
            pickerNewName = state.params.query.trimmingCharacters(in: .whitespaces)
        }
        showProjectPicker = true
    }
}

// MARK: - Project Picker Sheet

private struct ProjectPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let projects: [PuzzleProject]
    @Binding var pickerMode: OpenversePanel.ProjectPickerMode
    @Binding var selectedProjectID: UUID?
    @Binding var newProjectName: String
    let imageCount: Int
    let onAdd: (PuzzleProject) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add to Project")
                .font(.headline)

            Text("Download \(imageCount) image\(imageCount == 1 ? "" : "s") into a project.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: $pickerMode) {
                Text("Existing project").tag(OpenversePanel.ProjectPickerMode.existing)
                Text("New project").tag(OpenversePanel.ProjectPickerMode.createNew)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch pickerMode {
            case .existing:
                if projects.isEmpty {
                    Text("No projects yet. Switch to \"New project\" to create one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Picker("Project:", selection: $selectedProjectID) {
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .padding(.horizontal)
                }

            case .createNew:
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add \(imageCount) Image\(imageCount == 1 ? "" : "s")") {
                    let project = resolveProject()
                    dismiss()
                    onAdd(project)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400)
    }

    private var canAdd: Bool {
        switch pickerMode {
        case .existing:
            return selectedProjectID != nil
        case .createNew:
            return !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func resolveProject() -> PuzzleProject {
        switch pickerMode {
        case .existing:
            if let id = selectedProjectID, let project = projects.first(where: { $0.id == id }) {
                return project
            }
            // Fallback: create new
            let project = PuzzleProject(name: "Openverse Images")
            appState.addProject(project)
            appState.saveProject(project)
            return project

        case .createNew:
            let name = newProjectName.trimmingCharacters(in: .whitespaces)
            let project = PuzzleProject(name: name.isEmpty ? "Openverse Images" : name)
            appState.addProject(project)
            appState.saveProject(project)
            return project
        }
    }
}

// MARK: - Result Card

private struct OpenverseResultCard: View {
    let image: OpenverseImage
    let isSelected: Bool
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 120)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }

                if isSelected {
                    ZStack {
                        Color.accentColor.opacity(0.3)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Title
            Text(image.title ?? "Untitled")
                .font(.caption)
                .lineLimit(1)

            // Dimensions and licence
            HStack(spacing: 4) {
                if let w = image.width, let h = image.height {
                    Text("\(w)x\(h)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(image.license.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Creator
            if let creator = image.creator {
                Text("by \(creator)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
