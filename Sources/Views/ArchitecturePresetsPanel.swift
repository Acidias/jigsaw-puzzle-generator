import SwiftUI

/// Panel shown when clicking "Architecture Presets" in the sidebar.
/// Lists all presets and lets users create new ones.
struct ArchitecturePresetsPanel: View {
    @ObservedObject var modelState: ModelState
    @Binding var selection: SidebarItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 40))
                        .foregroundStyle(.teal)
                    Text("Architecture Presets")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create and manage reusable network architecture configurations")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)

                // Preset list
                if modelState.presets.isEmpty {
                    Text("No presets available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(modelState.presets) { preset in
                            presetRow(preset)
                            if preset.id != modelState.presets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // New preset button
                Button {
                    let preset = ArchitecturePreset(name: "New Preset", architecture: SiameseArchitecture())
                    modelState.addPreset(preset)
                    selection = .preset(preset.id)
                } label: {
                    Label("New Preset", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private func presetRow(_ preset: ArchitecturePreset) -> some View {
        Button {
            selection = .preset(preset.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.isBuiltIn ? "lock.rectangle.stack" : "rectangle.stack")
                    .foregroundStyle(preset.isBuiltIn ? .orange : .teal)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .fontWeight(.medium)
                        if preset.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(presetSummary(preset.architecture))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func presetSummary(_ arch: SiameseArchitecture) -> String {
        let blocks = arch.convBlocks.count
        let filters = arch.convBlocks.map { String($0.filters) }.joined(separator: " > ")
        return "\(blocks) blocks (\(filters)), \(arch.embeddingDimension)-d, \(arch.epochs) epochs"
    }
}

/// Detail view for editing a specific architecture preset.
struct PresetDetailView: View {
    @ObservedObject var preset: ArchitecturePreset
    @ObservedObject var modelState: ModelState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Name editor
                GroupBox("Preset") {
                    HStack {
                        Text("Name:")
                            .font(.callout)
                        TextField("Preset name", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: preset.name) { _, _ in
                                modelState.savePreset(preset)
                            }
                    }
                    .padding(8)
                }

                // Reuse the existing architecture editor
                ArchitectureEditorView(architecture: $preset.architecture)
                    .onChange(of: preset.architecture) { _, _ in
                        modelState.savePreset(preset)
                    }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle(preset.name)
    }
}
