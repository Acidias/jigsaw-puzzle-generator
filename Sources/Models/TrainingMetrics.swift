import Foundation

/// A single data point for charting (one epoch).
struct MetricPoint: Codable, Identifiable, Equatable {
    var id: Int { epoch }
    let epoch: Int
    let value: Double
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
        bestEpoch: Int? = nil
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
    }
}
