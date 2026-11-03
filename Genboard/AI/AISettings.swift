import Foundation
import Observation
import Security

@Observable
final class AISettings {
    var chatModel: String { didSet { defaults.set(chatModel, forKey: "ai.chatModel") } }
    var transcriptionModel: String { didSet { defaults.set(transcriptionModel, forKey: "ai.transcriptionModel") } }
    var summaryModel: String { didSet { defaults.set(summaryModel, forKey: "ai.summaryModel") } }
    var effort: String { didSet { defaults.set(effort, forKey: "ai.effort") } }
    private(set) var hasAPIKey = Keychain.apiKey != nil

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        chatModel = defaults.string(forKey: "ai.chatModel") ?? "claude-opus-5-5"
        transcriptionModel = defaults.string(forKey: "ai.transcriptionModel") ?? "claude-opus-5-5"
        summaryModel = defaults.string(forKey: "ai.summaryModel") ?? "claude-haiku-5-5"
        effort = defaults.string(forKey: "ai.effort") ?? "medium"
    }

    func setAPIKey(_ key: String) {
        Keychain.setAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        hasAPIKey = Keychain.apiKey != nil
    }
}

enum Keychain {
    private static let service = "Genboard.AnthropicAPIKey"
    private static let account = "default"

    /// The stored key, falling back to ANTHROPIC_API_KEY when launched from a shell.
    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        return env?.isEmpty == false ? env : nil
    }

    static func setAPIKey(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
