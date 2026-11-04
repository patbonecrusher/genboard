import Foundation

enum AIContentPart {
    case text(String)
    case jpeg(Data)
}

/// One conversation turn. Content is stored as the API's JSON block array so assistant turns
/// (including thinking blocks) can be replayed to the model byte-for-byte.
struct AITurn {
    enum Role: String { case user, assistant }
    let role: Role
    let contentJSON: Data

    static func user(_ parts: [AIContentPart]) -> AITurn {
        let blocks: [[String: Any]] = parts.map { part in
            switch part {
            case .text(let text):
                ["type": "text", "text": text]
            case .jpeg(let data):
                ["type": "image",
                 "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
            }
        }
        // Only strings and nested dictionaries: serialization cannot fail.
        return AITurn(role: .user, contentJSON: try! JSONSerialization.data(withJSONObject: blocks))
    }
}

struct AIUsage {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var totalInput: Int { input + cacheRead + cacheWrite }
}

struct AIReply {
    let text: String
    let assistantTurn: AITurn
    let usage: AIUsage
}

enum AIError: LocalizedError {
    case missingAPIKey
    case localUnavailable(String)
    case http(Int, String)
    case refused(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Anthropic API key in Settings (⌘,)."
        case .localUnavailable(let url): "Couldn't reach the local model at \(url). Start it with mlx_lm.server, or check the address in Settings (⌘,)."
        case .http(let status, let message): "The API returned \(status): \(message)"
        case .refused(let explanation): "The model declined: \(explanation)"
        case .badResponse: "The API returned a response Genboard couldn't read."
        }
    }
}

/// Claude (`ClaudeProvider`) or a model running on this Mac (`LocalProvider`).
protocol AIProvider {
    func send(model: String, effort: String, system: String, turns: [AITurn],
              jsonSchema: [String: Any]?) async throws -> AIReply
}

enum ModelCatalog {
    struct Model: Identifiable {
        let id: String
        let name: String
        /// USD per million tokens.
        let inputPrice: Double
        let outputPrice: Double
    }

    static let all: [Model] = [
        Model(id: "claude-opus-5-5", name: "Claude Opus 5.5", inputPrice: 4, outputPrice: 20),
        Model(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", inputPrice: 2, outputPrice: 10),
        Model(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", inputPrice: 0.10, outputPrice: 0.50),
        Model(id: localID, name: "Local model (MLX)", inputPrice: 0, outputPrice: 0),
    ]

    /// The model id that routes to the local server instead of Claude.
    static let localID = "local"

    static func model(_ id: String) -> Model { all.first { $0.id == id } ?? all[0] }

    /// Approximate: cache writes bill at 1.25× input and cache reads at 0.1× input.
    static func cost(model id: String, usage: AIUsage) -> Double {
        let model = model(id)
        let input = Double(usage.input) + Double(usage.cacheWrite) * 1.25 + Double(usage.cacheRead) * 0.1
        return (input * model.inputPrice + Double(usage.output) * model.outputPrice) / 1_000_000
    }
}
