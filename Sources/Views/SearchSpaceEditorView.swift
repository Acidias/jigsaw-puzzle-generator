import SwiftUI

/// Reusable component for editing AutoML search dimensions.
/// Displays searchable parameters grouped by section with toggleable range editors.
struct SearchSpaceEditorView: View {
    @Binding var dimensions: [SearchDimension]
    let baseArchitecture: SiameseArchitecture

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(SearchParamSection.allCases, id: \.rawValue) { section in
                if !section.params.isEmpty {
                    GroupBox(section.rawValue) {
                        VStack(spacing: 8) {
                            ForEach(section.params) { param in
                                paramRow(param)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Parameter Row

    private func paramRow(_ param: SearchableParam) -> some View {
        let isActive = dimensions.contains { $0.param == param }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(param.displayName, isOn: Binding(
                    get: { isActive },
                    set: { enabled in
                        if enabled {
                            dimensions.append(param.defaultDimension)
                        } else {
                            dimensions.removeAll { $0.param == param }
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                Spacer()
            }

            if isActive, let dimIndex = dimensions.firstIndex(where: { $0.param == param }) {
                dimensionEditor(param: param, index: dimIndex)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Dimension Editors

    @ViewBuilder
    private func dimensionEditor(param: SearchableParam, index: Int) -> some View {
        let dim = dimensions[index]

        switch dim {
        case .intRange(_, let low, let high, let step):
            HStack(spacing: 12) {
                Text("Range:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Min:")
                        .font(.caption)
                    TextField("", value: Binding(
                        get: { low },
                        set: { newLow in
                            dimensions[index] = .intRange(param: param, low: newLow, high: high, step: step)
                        }
                    ), format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                HStack(spacing: 4) {
                    Text("Max:")
                        .font(.caption)
                    TextField("", value: Binding(
                        get: { high },
                        set: { newHigh in
                            dimensions[index] = .intRange(param: param, low: low, high: newHigh, step: step)
                        }
                    ), format: .number)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                HStack(spacing: 4) {
                    Text("Step:")
                        .font(.caption)
                    TextField("", value: Binding(
                        get: { step },
                        set: { newStep in
                            dimensions[index] = .intRange(param: param, low: low, high: high, step: max(1, newStep))
                        }
                    ), format: .number)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }
            }

        case .floatRange(_, let low, let high, let log):
            HStack(spacing: 12) {
                Text("Range:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Min:")
                        .font(.caption)
                    TextField("", value: Binding(
                        get: { low },
                        set: { newLow in
                            dimensions[index] = .floatRange(param: param, low: newLow, high: high, log: log)
                        }
                    ), format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                HStack(spacing: 4) {
                    Text("Max:")
                        .font(.caption)
                    TextField("", value: Binding(
                        get: { high },
                        set: { newHigh in
                            dimensions[index] = .floatRange(param: param, low: low, high: newHigh, log: log)
                        }
                    ), format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                Toggle("Log scale", isOn: Binding(
                    get: { log },
                    set: { newLog in
                        dimensions[index] = .floatRange(param: param, low: low, high: high, log: newLog)
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }

        case .categorical(_, let choices):
            HStack(spacing: 8) {
                Text("Choices:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let allChoices = availableChoices(for: param)
                ForEach(allChoices, id: \.self) { choice in
                    Toggle(displayChoice(param: param, choice: choice), isOn: Binding(
                        get: { choices.contains(choice) },
                        set: { included in
                            var newChoices = choices
                            if included {
                                if !newChoices.contains(choice) {
                                    newChoices.append(choice)
                                }
                            } else {
                                newChoices.removeAll { $0 == choice }
                                // Must have at least one choice
                                if newChoices.isEmpty { return }
                            }
                            dimensions[index] = .categorical(param: param, choices: newChoices)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private func availableChoices(for param: SearchableParam) -> [String] {
        switch param {
        case .filtersBase:
            return ["16", "32", "64"]
        case .kernelSize:
            return ["3", "5"]
        case .useBatchNorm, .useFourClass, .useSeamOnly:
            return ["true", "false"]
        case .embeddingDimension:
            return ["128", "256", "512"]
        case .comparisonMethod:
            return ["l1", "l2", "concat"]
        case .batchSize:
            return ["16", "32", "64", "128"]
        default:
            return []
        }
    }

    private func displayChoice(param: SearchableParam, choice: String) -> String {
        switch param {
        case .useBatchNorm, .useFourClass, .useSeamOnly:
            return choice == "true" ? "Yes" : "No"
        case .comparisonMethod:
            switch choice {
            case "l1": return "L1"
            case "l2": return "L2"
            case "concat": return "Concat"
            default: return choice
            }
        default:
            return choice
        }
    }
}
