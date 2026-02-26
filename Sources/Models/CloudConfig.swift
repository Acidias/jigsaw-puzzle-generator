import Foundation

/// SSH connection configuration for cloud training.
struct CloudConfig: Codable, Equatable {
    var hostname: String
    var username: String
    var sshKeyPath: String
    var port: Int
    var remoteWorkDir: String

    init(
        hostname: String = "",
        username: String = "root",
        sshKeyPath: String = "~/.ssh/id_rsa",
        port: Int = 22,
        remoteWorkDir: String = "/workspace/training"
    ) {
        self.hostname = hostname
        self.username = username
        self.sshKeyPath = sshKeyPath
        self.port = port
        self.remoteWorkDir = remoteWorkDir
    }

    /// Whether the config has the minimum fields set for a connection.
    var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && FileManager.default.fileExists(atPath: resolvedKeyPath)
    }

    /// Expand ~ in the SSH key path to the full home directory.
    var resolvedKeyPath: String {
        NSString(string: sshKeyPath).expandingTildeInPath
    }
}

/// Persistence for the singleton cloud config file.
/// Saves to ~/Library/Application Support/JigsawPuzzleGenerator/cloud_config.json.
enum CloudConfigStore {

    private static var configPath: URL {
        ProjectStore.appSupportDirectory.appendingPathComponent("cloud_config.json")
    }

    static func load() -> CloudConfig {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path.path) else {
            return CloudConfig()
        }
        guard let data = try? Data(contentsOf: path) else {
            return CloudConfig()
        }
        return (try? JSONDecoder().decode(CloudConfig.self, from: data)) ?? CloudConfig()
    }

    static func save(_ config: CloudConfig) {
        let path = configPath
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: path)
        } catch {
            print("CloudConfigStore: Failed to save config: \(error)")
        }
    }
}
