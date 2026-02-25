import AppKit
import Foundation

/// Status of a single image in the batch queue.
enum BatchItemStatus: Equatable {
    case pending
    case generating(progress: Double)
    case completed(pieceCount: Int)
    case skipped(reason: String)
    case failed(reason: String)

    var isFinished: Bool {
        switch self {
        case .completed, .skipped, .failed: return true
        default: return false
        }
    }
}

/// One image in the batch processing queue.
@MainActor
class BatchItem: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let sourceImage: NSImage
    let sourceImageURL: URL?
    let imageWidth: Int
    let imageHeight: Int
    /// Attribution and licence info (non-nil for Openverse images).
    let attribution: ImageAttribution?

    @Published var status: BatchItemStatus = .pending
    /// Populated after successful generation.
    var puzzleImage: PuzzleImage?

    init(name: String, sourceImage: NSImage, sourceImageURL: URL?, attribution: ImageAttribution? = nil) {
        self.name = name
        self.sourceImage = sourceImage
        self.sourceImageURL = sourceImageURL
        self.attribution = attribution

        if let rep = sourceImage.representations.first, rep.pixelsWide > 0 {
            self.imageWidth = rep.pixelsWide
            self.imageHeight = rep.pixelsHigh
        } else {
            self.imageWidth = Int(sourceImage.size.width)
            self.imageHeight = Int(sourceImage.size.height)
        }
    }
}

/// Shared configuration for all images in a batch.
struct BatchConfiguration {
    var puzzleConfig = PuzzleConfiguration()
    /// Skip images whose shortest side is below this value (0 = no minimum).
    var minimumImageDimension: Int = 0
    /// Automatically export each image after generation.
    var autoExport: Bool = false
    /// Directory for auto-export output.
    var exportDirectory: URL?
}

/// Central state for a batch processing session.
@MainActor
class BatchState: ObservableObject {
    @Published var items: [BatchItem] = []
    @Published var configuration = BatchConfiguration()
    @Published var isRunning = false
    @Published var isCancelled = false

    // MARK: - Computed Properties

    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let total = Double(items.count)
        var progress = 0.0
        for item in items {
            switch item.status {
            case .pending:
                break
            case .generating(let p):
                progress += p
            case .completed, .skipped, .failed:
                progress += 1.0
            }
        }
        return progress / total
    }

    var completedCount: Int {
        items.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    var skippedCount: Int {
        items.filter {
            if case .skipped = $0.status { return true }
            return false
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var processedCount: Int {
        items.filter { $0.status.isFinished }.count
    }

    var isComplete: Bool {
        !items.isEmpty && items.allSatisfy { $0.status.isFinished }
    }

    // MARK: - Actions

    func addImages(from urls: [URL]) {
        for url in urls {
            guard let image = NSImage(contentsOf: url) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let item = BatchItem(name: name, sourceImage: image, sourceImageURL: url)
            items.append(item)
        }
    }

    func clearAll() {
        cleanup()
        items.removeAll()
    }

    func startBatch(appState: AppState, project: PuzzleProject) {
        guard !isRunning else { return }
        isRunning = true
        isCancelled = false

        for item in items {
            if item.status.isFinished {
                item.puzzleImage = nil
                item.status = .pending
            }
        }

        Task {
            var config = configuration.puzzleConfig
            config.validate()
            configuration.puzzleConfig = config

            for item in items {
                if isCancelled { break }
                guard case .pending = item.status else { continue }

                if let reason = skipReason(for: item) {
                    item.status = .skipped(reason: reason)
                    continue
                }

                item.status = .generating(progress: 0)

                let generator = PuzzleGenerator()
                let result = await generator.generate(
                    image: item.sourceImage,
                    imageURL: item.sourceImageURL,
                    configuration: config,
                    onProgress: { progress in
                        Task { @MainActor in
                            item.status = .generating(progress: progress)
                        }
                    }
                )

                switch result {
                case .success(let generation):
                    // Create image + cut
                    let puzzleImage = PuzzleImage(
                        name: item.name,
                        sourceImage: item.sourceImage,
                        sourceImageURL: item.sourceImageURL
                    )
                    puzzleImage.attribution = item.attribution

                    let cut = PuzzleCut(configuration: config)
                    cut.pieces = generation.pieces
                    cut.linesImage = generation.linesImage
                    cut.outputDirectory = generation.outputDirectory
                    puzzleImage.cuts.append(cut)

                    item.puzzleImage = puzzleImage
                    item.status = .completed(pieceCount: generation.actualPieceCount)

                    // Add to target project and persist
                    appState.addImage(puzzleImage, to: project)
                    ProjectStore.copySourceImage(puzzleImage, to: project)
                    ProjectStore.moveGeneratedPieces(for: cut, imageID: puzzleImage.id, in: project)
                    ProjectStore.saveLinesOverlay(for: cut, imageID: puzzleImage.id, in: project)
                    appState.saveProject(project)

                    // Auto-export if enabled
                    if configuration.autoExport, let dir = configuration.exportDirectory {
                        do {
                            try ExportService.export(
                                cut: cut,
                                imageName: puzzleImage.name,
                                imageWidth: puzzleImage.imageWidth,
                                imageHeight: puzzleImage.imageHeight,
                                attribution: puzzleImage.attribution,
                                to: dir
                            )
                        } catch {
                            // Export failure doesn't change item status
                        }
                    }

                case .failure(let error):
                    item.status = .failed(reason: error.errorDescription ?? "Unknown error")
                }
            }

            isRunning = false
        }
    }

    func cancelBatch() {
        isCancelled = true
    }

    func exportAll(to directory: URL) {
        for item in items {
            guard case .completed = item.status, let puzzleImage = item.puzzleImage else { continue }
            for cut in puzzleImage.cuts {
                try? ExportService.export(
                    cut: cut,
                    imageName: puzzleImage.name,
                    imageWidth: puzzleImage.imageWidth,
                    imageHeight: puzzleImage.imageHeight,
                    attribution: puzzleImage.attribution,
                    to: directory
                )
            }
        }
    }

    func cleanup() {
        for item in items {
            if let img = item.puzzleImage {
                for cut in img.cuts {
                    cut.cleanupOutputDirectory()
                }
            }
            item.puzzleImage = nil
        }
    }

    // MARK: - Skip Logic

    private func skipReason(for item: BatchItem) -> String? {
        let minDim = configuration.minimumImageDimension
        if minDim > 0 {
            let shortest = min(item.imageWidth, item.imageHeight)
            if shortest < minDim {
                return "Image too small (\(shortest)px shortest side, minimum is \(minDim)px)"
            }
        }

        let config = configuration.puzzleConfig
        let cellWidth = CGFloat(item.imageWidth) / CGFloat(config.columns)
        let cellHeight = CGFloat(item.imageHeight) / CGFloat(config.rows)
        if cellWidth < 20 || cellHeight < 20 {
            return "Pieces would be too small (\(Int(cellWidth))x\(Int(cellHeight))px per cell)"
        }

        return nil
    }
}
