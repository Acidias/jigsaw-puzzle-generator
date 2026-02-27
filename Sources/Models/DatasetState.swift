import Foundation

/// Category of a dataset pair for ML training.
enum DatasetCategory: String, CaseIterable {
    /// Correct match - same image, same cut. Shapes interlock and image content matches.
    case correct = "correct"
    /// Wrong: shapes interlock (same GridEdges) but image content differs.
    case wrongShapeMatch = "wrong_shape_match"
    /// Wrong: correct neighbours but presented in swapped order (right on left, left on right).
    case wrongOrientation = "wrong_orientation"
    /// Wrong: same image content near seam but shapes don't interlock (different GridEdges).
    case wrongImageMatch = "wrong_image_match"
    /// Wrong: different images and different cuts. Neither shape nor content matches.
    case wrongNothing = "wrong_nothing"

    var label: Int {
        switch self {
        case .correct: return 1
        case .wrongShapeMatch, .wrongOrientation, .wrongImageMatch, .wrongNothing: return 0
        }
    }

    var displayName: String {
        switch self {
        case .correct: return "Correct"
        case .wrongShapeMatch: return "Shape match"
        case .wrongOrientation: return "Wrong orientation"
        case .wrongImageMatch: return "Image match"
        case .wrongNothing: return "Nothing"
        }
    }
}

/// Train/test/validation split.
enum DatasetSplit: String, CaseIterable {
    case train
    case test
    case valid
}

/// A single generated piece in the dataset temp storage.
struct DatasetPiece {
    let imageID: UUID
    let cutIndex: Int
    let pieceIndex: Int
    let gridRow: Int
    let gridCol: Int
    let pngPath: URL
}

/// A pair of pieces forming one training example.
struct DatasetPair {
    let left: DatasetPiece
    let right: DatasetPiece
    let category: DatasetCategory
    let pairID: Int
    let direction: String       // "R" (horizontal/right) or "D" (vertical/down)
    let leftEdgeIndex: Int      // clockwise from top: 0=top, 1=right, 2=bottom, 3=left
}

/// Configuration for dataset generation.
struct DatasetConfiguration {
    var projectID: UUID?
    var rows: Int = 1
    var columns: Int = 2
    var pieceSize: Int = 224
    var pieceFill: PieceFill = .black
    var cutsPerImage: Int = 10
    var correctCount: Int = 500
    var wrongShapeMatchCount: Int = 500
    var wrongOrientationCount: Int = 500
    var wrongImageMatchCount: Int = 500
    var wrongNothingCount: Int = 500
    var trainRatio: Double = 0.70
    var testRatio: Double = 0.15
    var validRatio: Double = 0.15
    /// Total pairs across all categories.
    var totalPairs: Int {
        correctCount + wrongShapeMatchCount + wrongOrientationCount + wrongImageMatchCount + wrongNothingCount
    }

    func count(for category: DatasetCategory) -> Int {
        switch category {
        case .correct: return correctCount
        case .wrongShapeMatch: return wrongShapeMatchCount
        case .wrongOrientation: return wrongOrientationCount
        case .wrongImageMatch: return wrongImageMatchCount
        case .wrongNothing: return wrongNothingCount
        }
    }

    func ratio(for split: DatasetSplit) -> Double {
        switch split {
        case .train: return trainRatio
        case .test: return testRatio
        case .valid: return validRatio
        }
    }
}

/// Status of dataset generation.
enum DatasetGenerationStatus: Equatable {
    case idle
    case generating(phase: String, progress: Double)
    case completed(pairCount: Int)
    case failed(reason: String)

    static func == (lhs: DatasetGenerationStatus, rhs: DatasetGenerationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.generating(let a, let b), .generating(let c, let d)): return a == c && b == d
        case (.completed(let a), .completed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

/// Central state for dataset generation.
@MainActor
class DatasetState: ObservableObject {
    @Published var configuration = DatasetConfiguration()
    @Published var status: DatasetGenerationStatus = .idle
    @Published var logMessages: [String] = []
    @Published var datasets: [PuzzleDataset] = []
    @Published var selectedDatasetID: UUID?

    var selectedDataset: PuzzleDataset? {
        guard let id = selectedDatasetID else { return nil }
        return datasets.first { $0.id == id }
    }

    var isRunning: Bool {
        if case .generating = status { return true }
        return false
    }

    var overallProgress: Double {
        if case .generating(_, let progress) = status { return progress }
        if case .completed = status { return 1.0 }
        return 0.0
    }

    func log(_ message: String) {
        logMessages.append(message)
    }

    func clearLog() {
        logMessages.removeAll()
    }

    // MARK: - Capacity Calculations

    /// Number of adjacent pair positions in the configured grid.
    /// Horizontal: rows * (cols - 1), vertical: (rows - 1) * cols.
    var pairPositions: Int {
        configuration.rows * (configuration.columns - 1)
        + (configuration.rows - 1) * configuration.columns
    }

    func correctPool(imageCount: Int) -> Int {
        imageCount * configuration.cutsPerImage * pairPositions
    }

    func orientationPool(imageCount: Int) -> Int {
        // Every correct pair can be swapped, so pool equals correctPool
        imageCount * configuration.cutsPerImage * pairPositions
    }

    func shapeMatchPool(imageCount: Int) -> Int {
        configuration.cutsPerImage * imageCount * (imageCount - 1) * pairPositions
    }

    func imageMatchPool(imageCount: Int) -> Int {
        imageCount * configuration.cutsPerImage * (configuration.cutsPerImage - 1) * pairPositions
    }

    func nothingPool(imageCount: Int) -> Int {
        imageCount * (imageCount - 1) * configuration.cutsPerImage * (configuration.cutsPerImage - 1) * pairPositions
    }

    // MARK: - Dataset Persistence

    func loadDatasets() {
        datasets = DatasetStore.loadAllDatasets()
    }

    func deleteDataset(_ dataset: PuzzleDataset) {
        DatasetStore.deleteDataset(id: dataset.id)
        datasets.removeAll { $0.id == dataset.id }
        if selectedDatasetID == dataset.id {
            selectedDatasetID = nil
        }
    }
}
