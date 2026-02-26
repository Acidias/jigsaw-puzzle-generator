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
        perCategoryResults: [String: CategoryResult]? = nil
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
    }
}
