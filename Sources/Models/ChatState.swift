import Foundation

// MARK: - LLM Provider & Model

enum LLMProvider: String, CaseIterable, Codable {
    case claude = "Claude"
    case openAI = "OpenAI"
}

struct LLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: LLMProvider
}

enum LLMModels {
    static let all: [LLMModel] = [
        LLMModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: .claude),
        LLMModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: .claude),
        LLMModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", provider: .claude),
        LLMModel(id: "gpt-5.2", name: "GPT-5.2", provider: .openAI),
        LLMModel(id: "gpt-5.2-chat-latest", name: "GPT-5.2 Instant", provider: .openAI),
        LLMModel(id: "gpt-4o", name: "GPT-4o", provider: .openAI),
        LLMModel(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: .openAI),
    ]

    static func models(for provider: LLMProvider) -> [LLMModel] {
        all.filter { $0.provider == provider }
    }

    static func defaultModel(for provider: LLMProvider) -> LLMModel {
        models(for: provider).first!
    }
}

// MARK: - Credential Store

enum ChatCredentialStore {
    private static let claudeKeyKey = "ai_chat_claude_api_key"
    private static let openAIKeyKey = "ai_chat_openai_api_key"
    private static let providerKey = "ai_chat_provider"
    private static let modelIDKey = "ai_chat_model_id"
    private static let showRawConversationKey = "ai_chat_show_raw_conversation"

    static var claudeAPIKey: String {
        get { UserDefaults.standard.string(forKey: claudeKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: claudeKeyKey) }
    }

    static var openAIAPIKey: String {
        get { UserDefaults.standard.string(forKey: openAIKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: openAIKeyKey) }
    }

    static var savedProvider: LLMProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let provider = LLMProvider(rawValue: raw) else { return .claude }
            return provider
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var savedModelID: String? {
        get { UserDefaults.standard.string(forKey: modelIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: modelIDKey) }
    }

    static var showRawConversation: Bool {
        get { UserDefaults.standard.bool(forKey: showRawConversationKey) }
        set { UserDefaults.standard.set(newValue, forKey: showRawConversationKey) }
    }

    static func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .claude: return claudeAPIKey
        case .openAI: return openAIAPIKey
        }
    }
}

// MARK: - Chat Messages

enum ChatRole: String, Codable {
    case user
    case assistant
    case toolUse
    case toolResult
}

struct ChatToolCall: Identifiable, Codable {
    let id: String
    let name: String
    let arguments: String  // raw JSON string
}

struct ToolResultImage: Codable {
    let base64Data: String
    let mediaType: String
    let label: String
}

struct ChatToolResult: Identifiable, Codable {
    let id: String
    let toolCallID: String
    let toolName: String
    let content: String
    var images: [ToolResultImage] = []
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var text: String
    let timestamp: Date
    var toolCalls: [ChatToolCall]
    var toolResults: [ChatToolResult]
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String = "",
        timestamp: Date = Date(),
        toolCalls: [ChatToolCall] = [],
        toolResults: [ChatToolResult] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
    }

    // Exclude isStreaming from persistence
    enum CodingKeys: String, CodingKey {
        case id, role, text, timestamp, toolCalls, toolResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        toolCalls = try container.decodeIfPresent([ChatToolCall].self, forKey: .toolCalls) ?? []
        toolResults = try container.decodeIfPresent([ChatToolResult].self, forKey: .toolResults) ?? []
        isStreaming = false  // Always false on load
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(toolCalls, forKey: .toolCalls)
        // Strip images from tool results before saving (too large to persist)
        let strippedResults = toolResults.map { result in
            ChatToolResult(
                id: result.id,
                toolCallID: result.toolCallID,
                toolName: result.toolName,
                content: result.content
            )
        }
        try container.encode(strippedResults, forKey: .toolResults)
    }
}

// MARK: - Chat State

@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var provider: LLMProvider
    @Published var selectedModelID: String
    @Published var error: String?
    @Published var showRawConversation: Bool

    var selectedModel: LLMModel {
        LLMModels.all.first { $0.id == selectedModelID }
            ?? LLMModels.defaultModel(for: provider)
    }

    var hasAPIKey: Bool {
        !ChatCredentialStore.apiKey(for: provider).isEmpty
    }

    init() {
        let savedProvider = ChatCredentialStore.savedProvider
        self.provider = savedProvider
        if let savedID = ChatCredentialStore.savedModelID,
           LLMModels.all.contains(where: { $0.id == savedID }) {
            self.selectedModelID = savedID
        } else {
            self.selectedModelID = LLMModels.defaultModel(for: savedProvider).id
        }
        self.showRawConversation = ChatCredentialStore.showRawConversation
    }

    func setProvider(_ newProvider: LLMProvider) {
        provider = newProvider
        ChatCredentialStore.savedProvider = newProvider
        // Switch to default model for new provider
        let defaultModel = LLMModels.defaultModel(for: newProvider)
        selectedModelID = defaultModel.id
        ChatCredentialStore.savedModelID = defaultModel.id
    }

    func setModel(_ modelID: String) {
        selectedModelID = modelID
        ChatCredentialStore.savedModelID = modelID
    }

    func setShowRawConversation(_ value: Bool) {
        showRawConversation = value
        ChatCredentialStore.showRawConversation = value
    }

    func addUserMessage(_ text: String) {
        let message = ChatMessage(role: .user, text: text)
        messages.append(message)
        saveSession()
    }

    func addAssistantMessage(streaming: Bool = true) -> UUID {
        let message = ChatMessage(role: .assistant, isStreaming: streaming)
        messages.append(message)
        return message.id
    }

    func appendToMessage(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    func finaliseMessage(id: UUID, toolCalls: [ChatToolCall] = []) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isStreaming = false
        messages[index].toolCalls = toolCalls
        saveSession()
    }

    func addToolResult(_ result: ChatToolResult) {
        let message = ChatMessage(
            role: .toolResult,
            text: result.content,
            toolResults: [result]
        )
        messages.append(message)
        saveSession()
    }

    func clearMessages() {
        messages.removeAll()
        error = nil
        saveSession()
    }

    // MARK: - Session Persistence

    private static var sessionDirectory: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("chat")
    }

    private static var sessionURL: URL {
        sessionDirectory.appendingPathComponent("session.json")
    }

    func saveSession() {
        let url = Self.sessionURL
        do {
            try FileManager.default.createDirectory(at: Self.sessionDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messages)
            try data.write(to: url, options: .atomic)
        } catch {
            print("ChatState: Failed to save session: \(error)")
        }
    }

    func loadSession() {
        let url = Self.sessionURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            messages = try decoder.decode([ChatMessage].self, from: data)
        } catch {
            print("ChatState: Failed to load session: \(error)")
        }
    }
}
