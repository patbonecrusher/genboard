import Foundation

/// Calls the Claude Messages API over HTTP (there is no official Swift SDK).
final class ClaudeProvider: AIProvider {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Models that accept server-side refusal fallbacks (`fallbacks: "default"`).
    private let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    func send(model: String, effort: String, system: String, turns: [AITurn],
              jsonSchema: [String: Any]?) async throws -> AIReply {
        guard let apiKey = Keychain.apiKey else { throw AIError.missingAPIKey }

        let messages: [[String: Any]] = try turns.map {
            ["role": $0.role.rawValue, "content": try JSONSerialization.jsonObject(with: $0.contentJSON)]
        }
        var outputConfig: [String: Any] = ["effort": effort]
        if let jsonSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": jsonSchema]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            "output_config": outputConfig,
            "cache_control": ["type": "ephemeral"],
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if fallbackModels.contains(model) {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw status == 200 ? AIError.badResponse : AIError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard status == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? String(decoding: data, as: UTF8.self)
            throw AIError.http(status, message)
        }
        if json["stop_reason"] as? String == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw AIError.refused(details?["explanation"] as? String ?? "no explanation given")
        }

        let content = json["content"] as? [[String: Any]] ?? []
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        let usageJSON = json["usage"] as? [String: Any] ?? [:]
        let usage = AIUsage(
            input: usageJSON["input_tokens"] as? Int ?? 0,
            output: usageJSON["output_tokens"] as? Int ?? 0,
            cacheRead: usageJSON["cache_read_input_tokens"] as? Int ?? 0,
            cacheWrite: usageJSON["cache_creation_input_tokens"] as? Int ?? 0
        )
        let assistantTurn = AITurn(role: .assistant, contentJSON: try JSONSerialization.data(withJSONObject: content))
        return AIReply(text: text, assistantTurn: assistantTurn, usage: usage)
    }
}
