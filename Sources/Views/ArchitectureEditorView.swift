import SwiftUI

/// Reusable editor for SiameseArchitecture configuration.
/// Used in both ModelTrainingPanel (create) and ModelDetailView (edit).
struct ArchitectureEditorView: View {
    @Binding var architecture: SiameseArchitecture

    var body: some View {
        VStack(spacing: 20) {
            // Network diagram
            GroupBox("Network Architecture") {
                NetworkDiagramView(architecture: $architecture)
            }

            convBlocksSection
            embeddingSection
            hyperparametersSection
            summarySection
        }
    }

    // MARK: - Conv Blocks

    private var convBlocksSection: some View {
        GroupBox("Convolutional Blocks") {
            VStack(spacing: 12) {
                ForEach(Array(architecture.convBlocks.enumerated()), id: \.element.id) { index, _ in
                    convBlockEditor(index: index)
                    if index < architecture.convBlocks.count - 1 {
                        Divider()
                    }
                }

                HStack {
                    Button {
                        let lastFilters = architecture.convBlocks.last?.filters ?? 32
                        architecture.convBlocks.append(
                            ConvBlock(filters: min(lastFilters * 2, 512))
                        )
                    } label: {
                        Label("Add Block", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(architecture.convBlocks.count >= 8)

                    if architecture.convBlocks.count > 1 {
                        Button {
                            architecture.convBlocks.removeLast()
                        } label: {
                            Label("Remove Last", systemImage: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(8)
        }
    }

    private func convBlockEditor(index: Int) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Block \(index + 1)")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Filters:")
                        .font(.caption)
                    TextField("32", value: $architecture.convBlocks[index].filters, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.convBlocks[index].filters, in: 8...512, step: 16)
                        .labelsHidden()
                }

                HStack(spacing: 4) {
                    Text("Kernel:")
                        .font(.caption)
                    Picker("", selection: $architecture.convBlocks[index].kernelSize) {
                        Text("3x3").tag(3)
                        Text("5x5").tag(5)
                        Text("7x7").tag(7)
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
            }

            HStack(spacing: 16) {
                Toggle("Batch Norm", isOn: $architecture.convBlocks[index].useBatchNorm)
                    .font(.caption)
                Toggle("Max Pool", isOn: $architecture.convBlocks[index].useMaxPool)
                    .font(.caption)
            }
        }
    }

    // MARK: - Embedding

    private var embeddingSection: some View {
        GroupBox("Embedding & Comparison") {
            VStack(spacing: 8) {
                HStack {
                    Text("Embedding dimension:")
                        .font(.callout)
                    TextField("128", value: $architecture.embeddingDimension, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.embeddingDimension, in: 16...1024, step: 16)
                        .labelsHidden()
                }

                Picker("Comparison method:", selection: $architecture.comparisonMethod) {
                    ForEach(ComparisonMethod.allCases, id: \.rawValue) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .font(.callout)

                HStack {
                    Text("Dropout:")
                        .font(.callout)
                    Slider(value: $architecture.dropout, in: 0.0...0.8, step: 0.05)
                    Text("\(architecture.dropout, specifier: "%.2f")")
                        .font(.callout.monospacedDigit())
                        .frame(width: 40)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Hyperparameters

    private var hyperparametersSection: some View {
        GroupBox("Training Hyperparameters") {
            VStack(spacing: 8) {
                HStack {
                    Text("Learning rate:")
                        .font(.callout)
                    TextField("0.001", value: $architecture.learningRate, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Batch size:")
                        .font(.callout)
                    Picker("", selection: $architecture.batchSize) {
                        Text("8").tag(8)
                        Text("16").tag(16)
                        Text("32").tag(32)
                        Text("64").tag(64)
                        Text("128").tag(128)
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Epochs:")
                        .font(.callout)
                    TextField("50", value: $architecture.epochs, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $architecture.epochs, in: 1...500, step: 10)
                        .labelsHidden()
                }

                Picker("Device:", selection: $architecture.devicePreference) {
                    ForEach(DevicePreference.allCases, id: \.rawValue) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .font(.callout)
            }
            .padding(8)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 4) {
                summaryRow("Input", "\(architecture.inputSize) x \(architecture.inputSize) x 3")
                summaryRow("Conv blocks", "\(architecture.convBlocks.count)")
                summaryRow("Flattened size", "\(architecture.flattenedSize)")
                summaryRow("Embedding", "\(architecture.embeddingDimension)-d")
                summaryRow("Comparison", architecture.comparisonMethod.displayName)
                Divider()
                summaryRow("Learning rate", "\(architecture.learningRate)")
                summaryRow("Batch size", "\(architecture.batchSize)")
                summaryRow("Epochs", "\(architecture.epochs)")
            }
            .padding(8)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}
