import Foundation

/// A hyperparameter that can be searched over during AutoML.
enum SearchableParam: String, Codable, CaseIterable, Identifiable {
    case numConvBlocks
    case filtersBase
    case kernelSize
    case useBatchNorm
    case embeddingDimension
    case comparisonMethod
    case dropout
    case learningRate
    case batchSize
    case epochs
    case useFourClass
    case useSeamOnly
    case seamWidth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .numConvBlocks: return "Conv Blocks"
        case .filtersBase: return "Base Filters"
        case .kernelSize: return "Kernel Size"
        case .useBatchNorm: return "Batch Norm"
        case .embeddingDimension: return "Embedding Dim"
        case .comparisonMethod: return "Comparison"
        case .dropout: return "Dropout"
        case .learningRate: return "Learning Rate"
        case .batchSize: return "Batch Size"
        case .epochs: return "Epochs"
        case .useFourClass: return "Four-class Mode"
        case .useSeamOnly: return "Seam-only Mode"
        case .seamWidth: return "Seam Width"
        }
    }

    /// Which section this parameter belongs to for UI grouping.
    var section: SearchParamSection {
        switch self {
        case .numConvBlocks, .filtersBase, .kernelSize, .useBatchNorm,
             .embeddingDimension, .comparisonMethod, .dropout:
            return .architecture
        case .learningRate, .batchSize, .epochs:
            return .training
        case .useFourClass, .useSeamOnly, .seamWidth:
            return .mode
        }
    }

    /// Sensible default dimension for this parameter.
    var defaultDimension: SearchDimension {
        switch self {
        case .numConvBlocks:
            return .intRange(param: self, low: 3, high: 6, step: 1)
        case .filtersBase:
            return .categorical(param: self, choices: ["16", "32", "64"])
        case .kernelSize:
            return .categorical(param: self, choices: ["3", "5"])
        case .useBatchNorm:
            return .categorical(param: self, choices: ["true", "false"])
        case .embeddingDimension:
            return .categorical(param: self, choices: ["128", "256", "512"])
        case .comparisonMethod:
            return .categorical(param: self, choices: ["l1", "l2", "concat"])
        case .dropout:
            return .floatRange(param: self, low: 0.1, high: 0.5, log: false)
        case .learningRate:
            return .floatRange(param: self, low: 0.0001, high: 0.01, log: true)
        case .batchSize:
            return .categorical(param: self, choices: ["16", "32", "64", "128"])
        case .epochs:
            return .intRange(param: self, low: 30, high: 150, step: 10)
        case .useFourClass:
            return .categorical(param: self, choices: ["true", "false"])
        case .useSeamOnly:
            return .categorical(param: self, choices: ["true", "false"])
        case .seamWidth:
            return .intRange(param: self, low: 16, high: 128, step: 16)
        }
    }
}

/// UI grouping for search parameters.
enum SearchParamSection: String, CaseIterable {
    case architecture = "Architecture"
    case training = "Training"
    case mode = "Mode"

    var params: [SearchableParam] {
        SearchableParam.allCases.filter { $0.section == self }
    }
}

/// A single dimension in the search space, mapping to Optuna suggest_* calls.
enum SearchDimension: Codable, Equatable, Identifiable {
    case intRange(param: SearchableParam, low: Int, high: Int, step: Int)
    case floatRange(param: SearchableParam, low: Double, high: Double, log: Bool)
    case categorical(param: SearchableParam, choices: [String])

    var id: String { param.rawValue }

    var param: SearchableParam {
        switch self {
        case .intRange(let p, _, _, _): return p
        case .floatRange(let p, _, _, _): return p
        case .categorical(let p, _): return p
        }
    }
}

/// What metric to optimise during the search.
enum OptimisationMetric: String, Codable, CaseIterable {
    case validAccuracy
    case validLoss
    case recallAtP70

    var displayName: String {
        switch self {
        case .validAccuracy: return "Validation Accuracy"
        case .validLoss: return "Validation Loss"
        case .recallAtP70: return "Recall @ P70"
        }
    }

    var direction: String {
        switch self {
        case .validAccuracy, .recallAtP70: return "maximize"
        case .validLoss: return "minimize"
        }
    }

    /// Python variable name used in the generated script.
    var pythonMetricName: String {
        switch self {
        case .validAccuracy: return "best_valid_acc"
        case .validLoss: return "best_valid_loss"
        case .recallAtP70: return "recall_at_p70"
        }
    }
}

/// Complete configuration for an AutoML hyperparameter search.
struct AutoMLConfiguration: Codable, Equatable {
    var baseArchitecture: SiameseArchitecture
    var dimensions: [SearchDimension]
    var numTrials: Int
    var usePruning: Bool
    var pruningStartupTrials: Int
    var optimisationMetric: OptimisationMetric

    init(
        baseArchitecture: SiameseArchitecture = SiameseArchitecture(),
        dimensions: [SearchDimension] = [],
        numTrials: Int = 20,
        usePruning: Bool = true,
        pruningStartupTrials: Int = 5,
        optimisationMetric: OptimisationMetric = .validAccuracy
    ) {
        self.baseArchitecture = baseArchitecture
        self.dimensions = dimensions
        self.numTrials = numTrials
        self.usePruning = usePruning
        self.pruningStartupTrials = pruningStartupTrials
        self.optimisationMetric = optimisationMetric
    }
}
