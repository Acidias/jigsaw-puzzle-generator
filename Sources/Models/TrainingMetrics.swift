import Foundation

/// A single data point for charting (one epoch).
struct MetricPoint: Codable, Identifiable, Equatable {
    var id: Int { epoch }
    let epoch: Int
    let value: Double
}

/// Binary confusion matrix (match vs non-match).
struct ConfusionMatrix: Codable, Equatable {
    let truePositives: Int
    let falsePositives: Int
    let falseNegatives: Int
    let trueNegatives: Int
}

/// Per-category prediction breakdown.
struct CategoryResult: Codable, Equatable {
    let total: Int
    let predictedMatch: Int
    let predictedNonMatch: Int
}

/// Test-set metrics at a fixed precision target for fair cross-model comparison.
/// precisionTarget is an integer percentage (e.g. 70 = 70%).
/// When the target is unachievable, status is "unachievable" and metric fields are nil.
struct StandardisedResult: Codable, Equatable {
    let precisionTarget: Int
    let status: String
    let threshold: Double?
    let precision: Double?
    let recall: Double?
    let accuracy: Double?
    let f1: Double?
    let predictedPositives: Int?
    let truePositives: Int?
    let falsePositives: Int?
    let falseNegatives: Int?
    let trueNegatives: Int?

    /// Custom decoder for backwards compatibility with old metrics.json files
    /// where precisionTarget was a Double (0.7) and status/confusion counts were absent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // precisionTarget: try Int first, then convert from Double
        if let intValue = try? container.decode(Int.self, forKey: .precisionTarget) {
            precisionTarget = intValue
        } else {
            let doubleValue = try container.decode(Double.self, forKey: .precisionTarget)
            precisionTarget = Int(doubleValue * 100)
        }

        // status: default to "achieved" for old files
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "achieved"

        // All metric fields are optional in new format; in old format they were required.
        // Use decodeIfPresent for all to handle both cases.
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold)
        precision = try container.decodeIfPresent(Double.self, forKey: .precision)
        recall = try container.decodeIfPresent(Double.self, forKey: .recall)
        accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)
        f1 = try container.decodeIfPresent(Double.self, forKey: .f1)
        predictedPositives = try container.decodeIfPresent(Int.self, forKey: .predictedPositives)
        truePositives = try container.decodeIfPresent(Int.self, forKey: .truePositives)
        falsePositives = try container.decodeIfPresent(Int.self, forKey: .falsePositives)
        falseNegatives = try container.decodeIfPresent(Int.self, forKey: .falseNegatives)
        trueNegatives = try container.decodeIfPresent(Int.self, forKey: .trueNegatives)
    }

    init(
        precisionTarget: Int,
        status: String,
        threshold: Double?,
        precision: Double?,
        recall: Double?,
        accuracy: Double?,
        f1: Double?,
        predictedPositives: Int? = nil,
        truePositives: Int? = nil,
        falsePositives: Int? = nil,
        falseNegatives: Int? = nil,
        trueNegatives: Int? = nil
    ) {
        self.precisionTarget = precisionTarget
        self.status = status
        self.threshold = threshold
        self.precision = precision
        self.recall = recall
        self.accuracy = accuracy
        self.f1 = f1
        self.predictedPositives = predictedPositives
        self.truePositives = truePositives
        self.falsePositives = falsePositives
        self.falseNegatives = falseNegatives
        self.trueNegatives = trueNegatives
    }
}

/// Ranking metrics measuring how well the model ranks correct pairs.
struct RankingMetrics: Codable, Equatable {
    let recallAt1: Double
    let recallAt5: Double
    let recallAt10: Double
    let edgeQueryCount: Int?    // number of edge groups assessed (per-edge ranking)
    let avgPoolSize: Double?    // average candidates per edge group

    init(recallAt1: Double, recallAt5: Double, recallAt10: Double,
         edgeQueryCount: Int? = nil, avgPoolSize: Double? = nil) {
        self.recallAt1 = recallAt1
        self.recallAt5 = recallAt5
        self.recallAt10 = recallAt10
        self.edgeQueryCount = edgeQueryCount
        self.avgPoolSize = avgPoolSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recallAt1 = try container.decode(Double.self, forKey: .recallAt1)
        recallAt5 = try container.decode(Double.self, forKey: .recallAt5)
        recallAt10 = try container.decode(Double.self, forKey: .recallAt10)
        edgeQueryCount = try container.decodeIfPresent(Int.self, forKey: .edgeQueryCount)
        avgPoolSize = try container.decodeIfPresent(Double.self, forKey: .avgPoolSize)
    }
}

/// 4-class classification metrics (correct/wrongShape/wrongImage/wrongNothing).
struct FourClassMetrics: Codable, Equatable {
    let accuracy: Double
    let perClassAccuracy: [String: Double]
    let confusionMatrix4x4: [[Int]]     // 4x4 matrix, rows=true, cols=predicted
}

/// Information about the training run for performance comparison.
struct TrainingRunInfo: Codable, Equatable {
    let batchSizeUsed: Int
    let ampEnabled: Bool
    let inputSizeUsed: Int
    let pairsPerSecond: Double?
}

/// Imported training metrics for visualisation.
struct TrainingMetrics: Codable, Equatable {
    var trainLoss: [MetricPoint]
    var validLoss: [MetricPoint]
    var trainAccuracy: [MetricPoint]
    var validAccuracy: [MetricPoint]

    // Optional extras
    var testLoss: Double?
    var testAccuracy: Double?
    var testPrecision: Double?
    var testRecall: Double?
    var testF1: Double?
    var trainingDurationSeconds: Double?
    var bestEpoch: Int?
    var confusionMatrix: ConfusionMatrix?
    var perCategoryResults: [String: CategoryResult]?
    var optimalThreshold: Double?
    var standardisedResults: [StandardisedResult]?
    var rankingMetrics: RankingMetrics?
    var trainingRunInfo: TrainingRunInfo?
    var fourClassMetrics: FourClassMetrics?

    init(
        trainLoss: [MetricPoint] = [],
        validLoss: [MetricPoint] = [],
        trainAccuracy: [MetricPoint] = [],
        validAccuracy: [MetricPoint] = [],
        testLoss: Double? = nil,
        testAccuracy: Double? = nil,
        testPrecision: Double? = nil,
        testRecall: Double? = nil,
        testF1: Double? = nil,
        trainingDurationSeconds: Double? = nil,
        bestEpoch: Int? = nil,
        confusionMatrix: ConfusionMatrix? = nil,
        perCategoryResults: [String: CategoryResult]? = nil,
        optimalThreshold: Double? = nil,
        standardisedResults: [StandardisedResult]? = nil,
        rankingMetrics: RankingMetrics? = nil,
        trainingRunInfo: TrainingRunInfo? = nil,
        fourClassMetrics: FourClassMetrics? = nil
    ) {
        self.trainLoss = trainLoss
        self.validLoss = validLoss
        self.trainAccuracy = trainAccuracy
        self.validAccuracy = validAccuracy
        self.testLoss = testLoss
        self.testAccuracy = testAccuracy
        self.testPrecision = testPrecision
        self.testRecall = testRecall
        self.testF1 = testF1
        self.trainingDurationSeconds = trainingDurationSeconds
        self.bestEpoch = bestEpoch
        self.confusionMatrix = confusionMatrix
        self.perCategoryResults = perCategoryResults
        self.optimalThreshold = optimalThreshold
        self.standardisedResults = standardisedResults
        self.rankingMetrics = rankingMetrics
        self.trainingRunInfo = trainingRunInfo
        self.fourClassMetrics = fourClassMetrics
    }
}
