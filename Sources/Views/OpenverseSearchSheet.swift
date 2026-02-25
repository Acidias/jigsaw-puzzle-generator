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

    func downloadSelected(into batchState: BatchState) {
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
                    batchState.addOpenverseImage(
                        name: name,
                        image: nsImage,
                        imageURL: tempURL,
                        attribution: image.toAttribution()
                    )
                } catch {
                    let name = image.title ?? image.id
                    downloadFailures.append(name)
                }
                downloadCompleted += 1
            }
            isDownloading = false
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
    @ObservedObject var batchState: BatchState
    @ObservedObject var state: OpenverseSearchState

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

                Button("Add to Batch") {
                    state.downloadSelected(into: batchState)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.selectedImageIDs.isEmpty || state.isDownloading)
            }
            .padding()
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
