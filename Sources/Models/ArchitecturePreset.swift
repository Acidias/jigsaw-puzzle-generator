import Foundation

/// A saved architecture configuration that can be reused across models.
/// Independent top-level entity (like PuzzleDataset and SiameseModel).
@MainActor
class ArchitecturePreset: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    var architecture: SiameseArchitecture
    let isBuiltIn: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        architecture: SiameseArchitecture,
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.architecture = architecture
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    // MARK: - Built-in Presets

    /// Deterministic UUIDs for built-in presets so they can be detected and re-seeded.
    private static let quickTestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let recommendedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let highCapacityID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let builtInIDs: Set<UUID> = [quickTestID, recommendedID, highCapacityID]

    static var defaults: [ArchitecturePreset] {
        [
            ArchitecturePreset(
                id: quickTestID,
                name: "Quick Test",
                architecture: SiameseArchitecture(
                    convBlocks: [
                        ConvBlock(filters: 32, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 64, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 128, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                    ],
                    embeddingDimension: 128,
                    dropout: 0.3,
                    learningRate: 0.001,
                    batchSize: 32,
                    epochs: 50
                ),
                isBuiltIn: true
            ),
            ArchitecturePreset(
                id: recommendedID,
                name: "Recommended",
                architecture: SiameseArchitecture(
                    convBlocks: [
                        ConvBlock(filters: 32, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 64, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 128, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 256, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 256, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                    ],
                    embeddingDimension: 256,
                    dropout: 0.4,
                    learningRate: 0.0005,
                    batchSize: 32,
                    epochs: 150
                ),
                isBuiltIn: true
            ),
            ArchitecturePreset(
                id: highCapacityID,
                name: "High Capacity",
                architecture: SiameseArchitecture(
                    convBlocks: [
                        ConvBlock(filters: 32, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 64, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 128, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 256, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 512, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                        ConvBlock(filters: 512, kernelSize: 3, useBatchNorm: true, useMaxPool: true),
                    ],
                    embeddingDimension: 512,
                    dropout: 0.5,
                    learningRate: 0.0003,
                    batchSize: 32,
                    epochs: 200
                ),
                isBuiltIn: true
            ),
        ]
    }
}

extension ArchitecturePreset: Equatable {
    nonisolated static func == (lhs: ArchitecturePreset, rhs: ArchitecturePreset) -> Bool {
        lhs.id == rhs.id
    }
}

extension ArchitecturePreset: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
