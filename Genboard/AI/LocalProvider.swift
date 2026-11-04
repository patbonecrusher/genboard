import Foundation

/// A model running on this Mac, served by `mlx_lm.server` (or LM Studio, or Ollama) through the
/// OpenAI-style `/v1/chat/completions` endpoint. Nothing leaves the computer and it costs nothing.
/// Most local models read text only, so images in a request are left out.
final class LocalProvider: AIProvider {
    let baseURL: URL
    let modelName: String
    private let session: URLSession

    init(baseURL: URL, modelName: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.session = session
    }

    func send(model: String, effort: String, system: String, turns: [AITurn],
              jsonSchema: [String: Any]?) async throws -> AIReply {
        var systemPrompt = system
        if let jsonSchema, let schema = try? JSONSerialization.data(withJSONObject: jsonSchema, options: [.sortedKeys]) {
            // Not every local server honors response_format, so the prompt asks for the shape too.
            systemPrompt += "\n\nReply with only a JSON object matching this JSON Schema, with no other text:\n"
                + String(decoding: schema, as: UTF8.self)
        }
        var body: [String: Any] = [
            "messages": Self.messages(system: systemPrompt, turns: turns),
            "max_tokens": 4096,
            "temperature": 0.3,
            "stream": false,
        ]
        if !modelName.isEmpty { body["model"] = modelName }
        if let jsonSchema {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["name": "reply", "schema": jsonSchema, "strict": true]]
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/chat/completions"), timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.localUnavailable(baseURL.absoluteString)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AIError.http(status, String(decoding: data, as: UTF8.self)) }
        var (text, usage) = try Self.parse(data)
        if jsonSchema != nil { text = Self.extractJSON(text) }
        // Stored in the same block format as Claude's turns, so a chat can switch between the two.
        let assistantTurn = AITurn(role: .assistant,
                                   contentJSON: try JSONSerialization.data(withJSONObject: [["type": "text", "text": text]]))
        return AIReply(text: text, assistantTurn: assistantTurn, usage: usage)
    }

    /// The models the server offers, to check the connection from Settings.
    func availableModels() async throws -> [String] {
        let (data, response) = try await session.data(from: baseURL.appending(path: "v1/models"))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.badResponse }
        return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    // MARK: Translation

    /// Claude-style turns (content blocks) as OpenAI-style messages. Text blocks are joined;
    /// images and thinking blocks are dropped.
    static func messages(system: String, turns: [AITurn]) -> [[String: Any]] {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for turn in turns {
            let blocks = (try? JSONSerialization.jsonObject(with: turn.contentJSON)) as? [[String: Any]] ?? []
            var text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if blocks.contains(where: { $0["type"] as? String == "image" }) {
                text = "[An image was attached, but this local model can't see images.]\n" + text
            }
            messages.append(["role": turn.role.rawValue, "content": text])
        }
        return messages
    }

    static func parse(_ data: Data) throws -> (String, AIUsage) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw AIError.badResponse }
        var text = message["content"] as? String ?? ""
        // Reasoning models wrap their thinking in <think>…</think>; only the answer is shown.
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        let usageJSON = json["usage"] as? [String: Any] ?? [:]
        let usage = AIUsage(input: usageJSON["prompt_tokens"] as? Int ?? 0, output: usageJSON["completion_tokens"] as? Int ?? 0)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), usage)
    }

    /// The JSON object in a reply that may be wrapped in a code fence or a sentence.
    static func extractJSON(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}
