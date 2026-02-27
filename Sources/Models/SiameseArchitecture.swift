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

/// Preferred compute device for training.
enum DevicePreference: String, Codable, CaseIterable {
    case auto
    case mps
    case cuda
    case cpu

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .mps: return "MPS (Apple GPU)"
        case .cuda: return "CUDA (NVIDIA GPU)"
        case .cpu: return "CPU"
        }
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

    /// Short label for compact table display.
    var shortName: String {
        switch self {
        case .l1Distance: return "L1"
        case .l2Distance: return "L2"
        case .concatenation: return "Cat"
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
    var devicePreference: DevicePreference
    var useNativeResolution: Bool
    var useMixedPrecision: Bool

    /// AdaptiveAvgPool2d reduces spatial dims to a fixed 4x4 grid before the
    /// embedding head, making flattened size independent of input resolution.
    static let adaptivePoolSize = 4

    var flattenedSize: Int {
        let lastFilters = convBlocks.last?.filters ?? 1
        return lastFilters * Self.adaptivePoolSize * Self.adaptivePoolSize
    }

    init(
        convBlocks: [ConvBlock]? = nil,
        embeddingDimension: Int = 128,
        comparisonMethod: ComparisonMethod = .l1Distance,
        dropout: Double = 0.3,
        learningRate: Double = 0.001,
        batchSize: Int = 32,
        epochs: Int = 50,
        inputSize: Int = 392,
        devicePreference: DevicePreference = .auto,
        useNativeResolution: Bool = false,
        useMixedPrecision: Bool = false
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
        self.devicePreference = devicePreference
        self.useNativeResolution = useNativeResolution
        self.useMixedPrecision = useMixedPrecision
    }

    /// Custom decoder for backwards compatibility with manifests that lack newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        convBlocks = try container.decode([ConvBlock].self, forKey: .convBlocks)
        embeddingDimension = try container.decode(Int.self, forKey: .embeddingDimension)
        comparisonMethod = try container.decode(ComparisonMethod.self, forKey: .comparisonMethod)
        dropout = try container.decode(Double.self, forKey: .dropout)
        learningRate = try container.decode(Double.self, forKey: .learningRate)
        batchSize = try container.decode(Int.self, forKey: .batchSize)
        epochs = try container.decode(Int.self, forKey: .epochs)
        inputSize = try container.decode(Int.self, forKey: .inputSize)
        devicePreference = try container.decodeIfPresent(DevicePreference.self, forKey: .devicePreference) ?? .auto
        useNativeResolution = try container.decodeIfPresent(Bool.self, forKey: .useNativeResolution) ?? false
        useMixedPrecision = try container.decodeIfPresent(Bool.self, forKey: .useMixedPrecision) ?? false
    }
}
