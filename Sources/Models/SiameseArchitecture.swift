import Foundation

/// A single convolutional block in the Siamese network.
struct ConvBlock: Codable, Identifiable, Equatable {
    let id: UUID
    var filters: Int
    var kernelSize: Int
    var useBatchNorm: Bool
    var useMaxPool: Bool

    init(
        id: UUID = UUID(),
        filters: Int = 32,
        kernelSize: Int = 3,
        useBatchNorm: Bool = true,
        useMaxPool: Bool = true
    ) {
        self.id = id
        self.filters = filters
        self.kernelSize = kernelSize
        self.useBatchNorm = useBatchNorm
        self.useMaxPool = useMaxPool
    }
}

/// How the two embedding vectors are compared.
enum ComparisonMethod: String, Codable, CaseIterable {
    case l1Distance = "l1"
    case l2Distance = "l2"
    case concatenation = "concat"

    var displayName: String {
        switch self {
        case .l1Distance: return "L1 Distance"
        case .l2Distance: return "L2 Distance"
        case .concatenation: return "Concatenation"
        }
    }
}

/// Full architecture configuration for a Siamese Neural Network.
struct SiameseArchitecture: Codable, Equatable {
    var convBlocks: [ConvBlock]
    var embeddingDimension: Int
    var comparisonMethod: ComparisonMethod
    var dropout: Double
    var learningRate: Double
    var batchSize: Int
    var epochs: Int
    var inputSize: Int

    /// Spatial dimensions are halved per MaxPool layer.
    /// Flattened size = last filter count * (inputSize / 2^poolCount)^2.
    var flattenedSize: Int {
        let poolCount = convBlocks.filter(\.useMaxPool).count
        let spatialDim = max(1, inputSize / (1 << poolCount))
        let lastFilters = convBlocks.last?.filters ?? 1
        return lastFilters * spatialDim * spatialDim
    }

    init(
        convBlocks: [ConvBlock]? = nil,
        embeddingDimension: Int = 128,
        comparisonMethod: ComparisonMethod = .l1Distance,
        dropout: Double = 0.3,
        learningRate: Double = 0.001,
        batchSize: Int = 32,
        epochs: Int = 50,
        inputSize: Int = 392
    ) {
        self.convBlocks = convBlocks ?? [
            ConvBlock(filters: 32, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
            ConvBlock(filters: 64, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
            ConvBlock(filters: 128, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
        ]
        self.embeddingDimension = embeddingDimension
        self.comparisonMethod = comparisonMethod
        self.dropout = dropout
        self.learningRate = learningRate
        self.batchSize = batchSize
        self.epochs = epochs
        self.inputSize = inputSize
    }
}
