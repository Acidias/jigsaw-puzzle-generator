import SwiftUI

struct AIChatPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var chatState: ChatState
    @ObservedObject var modelState: ModelState
    @ObservedObject var datasetState: DatasetState

    @State private var chatTask: Task<Void, Never>?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()

            // Messages
            if chatState.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()

            // Input
            inputBar
        }
        .onDisappear {
            chatTask?.cancel()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.purple)
            Text("AI Chat")
                .font(.headline)

            Spacer()

            Text(chatState.selectedModel.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showSettings) {
                ChatSettingsView(chatState: chatState)
            }

            Button {
                chatTask?.cancel()
                chatState.clearMessages()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(chatState.messages.isEmpty && !chatState.isStreaming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Ask about your models, datasets, and training results")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 4) {
                suggestionButton("List my models and their accuracy")
                suggestionButton("Compare my trained models")
                suggestionButton("What architecture changes might improve R@1?")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            chatState.inputText = text
            sendMessage()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(text)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(chatState.isStreaming)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chatState.messages) { message in
                        ChatMessageView(message: message)
                    }

                    if let error = chatState.error {
                        errorView(error)
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: chatState.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chatState.messages.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about models, datasets, metrics...", text: $chatState.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    sendMessage()
                }

            Button {
                if chatState.isStreaming {
                    chatTask?.cancel()
                } else {
                    sendMessage()
                }
            } label: {
                Image(systemName: chatState.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend || chatState.isStreaming ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend && !chatState.isStreaming)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !chatState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !chatState.isStreaming
        && chatState.hasAPIKey
    }

    // MARK: - Send

    private func sendMessage() {
        let text = chatState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatState.isStreaming, chatState.hasAPIKey else { return }

        chatState.inputText = ""
        chatState.error = nil
        chatState.addUserMessage(text)

        chatTask = Task {
            await LLMService.streamChat(
                chatState: chatState,
                modelState: modelState,
                datasetState: datasetState,
                appState: appState
            )
        }
    }
}
