import Foundation

/// Codable DTO for persisting a dataset to disk as manifest.json.
struct DatasetManifest: Codable {
    let id: UUID
    var name: String
    let sourceProjectID: UUID
    let sourceProjectName: String
    let createdAt: Date
    // Config
    let rows: Int
    let columns: Int
    let pieceSize: Int
    let pieceFill: String
    let cutsPerImage: Int
    let trainRatio: Double
    let testRatio: Double
    let validRatio: Double
    let correctCount: Int
    let wrongShapeMatchCount: Int
    let wrongImageMatchCount: Int
    let wrongNothingCount: Int
    // Counts
    var splitCounts: [String: [String: Int]]
    var totalPairs: Int

    /// Decode with backwards compatibility - old manifests default to 1x2 grid.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceProjectID = try container.decode(UUID.self, forKey: .sourceProjectID)
        sourceProjectName = try container.decode(String.self, forKey: .sourceProjectName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 1
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 2
        pieceSize = try container.decode(Int.self, forKey: .pieceSize)
        pieceFill = try container.decode(String.self, forKey: .pieceFill)
        cutsPerImage = try container.decode(Int.self, forKey: .cutsPerImage)
        trainRatio = try container.decode(Double.self, forKey: .trainRatio)
        testRatio = try container.decode(Double.self, forKey: .testRatio)
        validRatio = try container.decode(Double.self, forKey: .validRatio)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        wrongShapeMatchCount = try container.decode(Int.self, forKey: .wrongShapeMatchCount)
        wrongImageMatchCount = try container.decode(Int.self, forKey: .wrongImageMatchCount)
        wrongNothingCount = try container.decode(Int.self, forKey: .wrongNothingCount)
        splitCounts = try container.decode([String: [String: Int]].self, forKey: .splitCounts)
        totalPairs = try container.decode(Int.self, forKey: .totalPairs)
    }

    /// Create a manifest from a runtime PuzzleDataset.
    @MainActor
    init(from dataset: PuzzleDataset) {
        self.id = dataset.id
        self.name = dataset.name
        self.sourceProjectID = dataset.sourceProjectID
        self.sourceProjectName = dataset.sourceProjectName
        self.createdAt = dataset.createdAt
        self.rows = dataset.configuration.rows
        self.columns = dataset.configuration.columns
        self.pieceSize = dataset.configuration.pieceSize
        self.pieceFill = dataset.configuration.pieceFill.rawValue
        self.cutsPerImage = dataset.configuration.cutsPerImage
        self.trainRatio = dataset.configuration.trainRatio
        self.testRatio = dataset.configuration.testRatio
        self.validRatio = dataset.configuration.validRatio
        self.correctCount = dataset.configuration.correctCount
        self.wrongShapeMatchCount = dataset.configuration.wrongShapeMatchCount
        self.wrongImageMatchCount = dataset.configuration.wrongImageMatchCount
        self.wrongNothingCount = dataset.configuration.wrongNothingCount
        self.totalPairs = dataset.totalPairs

        var counts: [String: [String: Int]] = [:]
        for (split, catCounts) in dataset.splitCounts {
            var catDict: [String: Int] = [:]
            for (cat, count) in catCounts {
                catDict[cat.rawValue] = count
            }
            counts[split.rawValue] = catDict
        }
        self.splitCounts = counts
    }

    /// Reconstruct a runtime PuzzleDataset from this manifest.
    @MainActor
    func toDataset() -> PuzzleDataset {
        var config = DatasetConfiguration()
        config.rows = rows
        config.columns = columns
        config.pieceSize = pieceSize
        config.pieceFill = PieceFill(rawValue: pieceFill) ?? .black
        config.cutsPerImage = cutsPerImage
        config.trainRatio = trainRatio
        config.testRatio = testRatio
        config.validRatio = validRatio
        config.correctCount = correctCount
        config.wrongShapeMatchCount = wrongShapeMatchCount
        config.wrongImageMatchCount = wrongImageMatchCount
        config.wrongNothingCount = wrongNothingCount

        var parsedCounts: [DatasetSplit: [DatasetCategory: Int]] = [:]
        for (splitStr, catDict) in splitCounts {
            guard let split = DatasetSplit(rawValue: splitStr) else { continue }
            var catCounts: [DatasetCategory: Int] = [:]
            for (catStr, count) in catDict {
                guard let cat = DatasetCategory(rawValue: catStr) else { continue }
                catCounts[cat] = count
            }
            parsedCounts[split] = catCounts
        }

        return PuzzleDataset(
            id: id,
            name: name,
            sourceProjectID: sourceProjectID,
            sourceProjectName: sourceProjectName,
            configuration: config,
            createdAt: createdAt,
            splitCounts: parsedCounts
        )
    }
}
