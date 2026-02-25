import SwiftUI
import UniformTypeIdentifiers

struct BatchProcessingView: View {
    @StateObject private var batchState = BatchState()
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Image list
            BatchImageList(batchState: batchState, isDragTargeted: $isDragTargeted)

            Divider()

            // Settings panel
            BatchSettingsPanel(configuration: $batchState.configuration)
                .padding()
                .disabled(batchState.isRunning)

            Divider()

            // Progress and controls
            VStack(spacing: 12) {
                if !batchState.items.isEmpty {
                    BatchProgressBar(batchState: batchState)
                }
                BatchControls(batchState: batchState)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Image List

private struct BatchImageList: View {
    @ObservedObject var batchState: BatchState
    @Binding var isDragTargeted: Bool

    var body: some View {
        Group {
            if batchState.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop images here or click \"Choose Images...\"")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 200)
    }

    private var itemList: some View {
        List {
            ForEach(batchState.items) { item in
                BatchItemRow(item: item)
            }
            .onDelete { offsets in
                guard !batchState.isRunning else { return }
                for index in offsets {
                    batchState.items[index].project?.cleanupOutputDirectory()
                }
                batchState.items.remove(atOffsets: offsets)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !batchState.isRunning else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          NSImage(contentsOf: url) != nil
                    else { return }
                    Task { @MainActor in
                        batchState.addImages(from: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Item Row

private struct BatchItemRow: View {
    @ObservedObject var item: BatchItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(nsImage: item.sourceImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Name and dimensions
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(item.imageWidth) x \(item.imageHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            statusView
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Pending")

        case .generating(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 80)

        case .completed(let pieceCount):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(pieceCount) pieces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .skipped(let reason):
            Image(systemName: "forward.fill")
                .foregroundStyle(.orange)
                .help(reason)

        case .failed(let reason):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(reason)
        }
    }
}

// MARK: - Settings Panel

private struct BatchSettingsPanel: View {
    @Binding var configuration: BatchConfiguration

    var body: some View {
        GroupBox("Batch Settings") {
            VStack(spacing: 12) {
                // Grid size controls
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns: \(configuration.puzzleConfig.columns)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(configuration.puzzleConfig.columns) },
                                    set: { configuration.puzzleConfig.columns = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $configuration.puzzleConfig.columns,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rows: \(configuration.puzzleConfig.rows)")
                            .font(.callout)
                            .fontWeight(.medium)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(configuration.puzzleConfig.rows) },
                                    set: { configuration.puzzleConfig.rows = Int($0) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                            Stepper(
                                "",
                                value: $configuration.puzzleConfig.rows,
                                in: 1...100
                            )
                            .labelsHidden()
                        }
                    }
                }

                Divider()

                // Minimum dimension and auto-export
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Text("Min. dimension:")
                            .font(.callout)
                        TextField(
                            "0",
                            value: $configuration.minimumImageDimension,
                            format: .number
                        )
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        Text("px")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .help("Skip images whose shortest side is below this value (0 = no minimum)")

                    Spacer()

                    Toggle("Auto-export", isOn: $configuration.autoExport)

                    if configuration.autoExport {
                        Button(configuration.exportDirectory == nil ? "Choose Folder..." : "Change...") {
                            chooseExportDirectory()
                        }
                        .controlSize(.small)

                        if let dir = configuration.exportDirectory {
                            Text(dir.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for batch export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        configuration.exportDirectory = url
    }
}

// MARK: - Progress Bar

private struct BatchProgressBar: View {
    @ObservedObject var batchState: BatchState

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: batchState.overallProgress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(batchState.processedCount) of \(batchState.items.count) images processed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(batchState.overallProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Controls

private struct BatchControls: View {
    @ObservedObject var batchState: BatchState

    var body: some View {
        HStack {
            // Choose and clear buttons
            Button("Choose Images...") {
                chooseImages()
            }
            .disabled(batchState.isRunning)

            if !batchState.items.isEmpty {
                Button("Clear All") {
                    batchState.clearAll()
                }
                .disabled(batchState.isRunning)
            }

            Spacer()

            // Summary badges
            if batchState.isComplete || batchState.isCancelled {
                HStack(spacing: 8) {
                    if batchState.completedCount > 0 {
                        Label("\(batchState.completedCount)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if batchState.skippedCount > 0 {
                        Label("\(batchState.skippedCount)", systemImage: "forward.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if batchState.failedCount > 0 {
                        Label("\(batchState.failedCount)", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Export All (when auto-export is off and there are completed items)
            if !batchState.configuration.autoExport && batchState.completedCount > 0 && !batchState.isRunning {
                Button("Export All") {
                    exportAll()
                }
            }

            // Start / Cancel button
            if batchState.isRunning {
                Button("Cancel") {
                    batchState.cancelBatch()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Start Batch") {
                    // Validate auto-export directory if enabled
                    if batchState.configuration.autoExport && batchState.configuration.exportDirectory == nil {
                        chooseExportDirectoryThenStart()
                        return
                    }
                    batchState.startBatch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(batchState.items.isEmpty)
            }
        }
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images for batch processing"

        guard panel.runModal() == .OK else { return }
        batchState.addImages(from: panel.urls)
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to export all puzzles"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        batchState.exportAll(to: url)
    }

    private func chooseExportDirectoryThenStart() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for batch export"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        batchState.configuration.exportDirectory = url
        batchState.startBatch()
    }
}
