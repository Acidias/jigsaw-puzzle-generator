import SwiftUI

struct ChatSettingsView: View {
    @ObservedObject var chatState: ChatState
    @State private var claudeKey: String = ChatCredentialStore.claudeAPIKey
    @State private var openAIKey: String = ChatCredentialStore.openAIAPIKey

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Chat Settings")
                .font(.headline)

            // Provider picker
            Picker("Provider", selection: Binding(
                get: { chatState.provider },
                set: { chatState.setProvider($0) }
            )) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            // Model picker
            Picker("Model", selection: Binding(
                get: { chatState.selectedModelID },
                set: { chatState.setModel($0) }
            )) {
                ForEach(LLMModels.models(for: chatState.provider)) { model in
                    Text(model.name).tag(model.id)
                }
            }

            Divider()

            // Claude OAuth section
            if chatState.provider == .claude {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude Account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let email = chatState.claudeOAuthEmail, ChatCredentialStore.isClaudeOAuthActive {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Signed in as \(email)")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button("Sign out") {
                                ClaudeOAuthService.signOut()
                                chatState.claudeOAuthEmail = nil
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            chatState.isOAuthSigningIn = true
                            Task {
                                do {
                                    let email = try await ClaudeOAuthService.authenticate()
                                    chatState.claudeOAuthEmail = email
                                } catch is CancellationError {
                                    // User cancelled - ignore
                                } catch ClaudeOAuthService.OAuthError.cancelled {
                                    // User closed window - ignore
                                } catch {
                                    chatState.error = error.localizedDescription
                                }
                                chatState.isOAuthSigningIn = false
                            }
                        } label: {
                            HStack {
                                if chatState.isOAuthSigningIn {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Signing in...")
                                } else {
                                    Image(systemName: "person.circle")
                                    Text("Sign in with Claude")
                                }
                            }
                        }
                        .disabled(chatState.isOAuthSigningIn)

                        Text("Use your Pro or Max plan's usage allowance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(.quaternary)
                        Text("or")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            // API Keys
            VStack(alignment: .leading, spacing: 8) {
                Text("API Keys")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Claude")
                        .frame(width: 60, alignment: .leading)
                    SecureField("sk-ant-...", text: $claudeKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: claudeKey) { _, newValue in
                            ChatCredentialStore.claudeAPIKey = newValue
                        }
                }

                HStack {
                    Text("OpenAI")
                        .frame(width: 60, alignment: .leading)
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openAIKey) { _, newValue in
                            ChatCredentialStore.openAIAPIKey = newValue
                        }
                }
            }

            if !chatState.hasAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No API key or account set for \(chatState.provider.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Show raw conversation", isOn: Binding(
                get: { chatState.showRawConversation },
                set: { chatState.setShowRawConversation($0) }
            ))
        }
        .padding()
        .frame(width: 320)
    }
}
