import Foundation
import Testing
@testable import Genboard

/// Answers every request with a canned OpenAI-style reply and remembers the last request body.
nonisolated final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply = Data()
    nonisolated(unsafe) static var lastBody: [String: Any] = [:]
    nonisolated(unsafe) static var lastPath = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path ?? ""
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }

    static func answer(_ content: String) {
        reply = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": content]]],
            "usage": ["prompt_tokens": 120, "completion_tokens": 30],
        ])
    }
}

@Suite(.serialized)
@MainActor
struct LocalProviderTests {
    private let provider = LocalProvider(baseURL: URL(string: "http://127.0.0.1:8080")!,
                                         modelName: "mlx-community/test", session: StubServer.session())

    @Test func sendsAChatCompletionAndReadsTheReply() async throws {
        StubServer.answer("<think>Hmm.</think>\nAntoine is the likelier father.")
        let reply = try await provider.send(model: ModelCatalog.localID, effort: "medium", system: "Be careful.",
                                            turns: [.user([.text("Who is the father?")])], jsonSchema: nil)
        #expect(StubServer.lastPath == "/v1/chat/completions")
        #expect(StubServer.lastBody["model"] as? String == "mlx-community/test")
        let messages = try #require(StubServer.lastBody["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect(messages[1]["content"] as? String == "Who is the father?")
        #expect(reply.text == "Antoine is the likelier father.")
        #expect(reply.usage.input == 120 && reply.usage.output == 30)
        #expect(ModelCatalog.cost(model: ModelCatalog.localID, usage: reply.usage) == 0)
    }

    @Test func asksForJSONAndExtractsIt() async throws {
        StubServer.answer("Here you go:\n```json\n{\"where_left_off\": \"Found it\", \"next_steps\": [], \"open_questions\": []}\n```")
        let schema: [String: Any] = ["type": "object", "properties": ["where_left_off": ["type": "string"]]]
        let reply = try await provider.send(model: ModelCatalog.localID, effort: "low", system: "Summarize.",
                                            turns: [.user([.text("Draft it.")])], jsonSchema: schema)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(reply.text.utf8)) as? [String: Any])
        #expect(json["where_left_off"] as? String == "Found it")
        let messages = try #require(StubServer.lastBody["messages"] as? [[String: Any]])
        #expect((messages[0]["content"] as? String)?.contains("JSON Schema") == true)
        #expect((StubServer.lastBody["response_format"] as? [String: Any])?["type"] as? String == "json_schema")
    }

    @Test func translatesClaudeTurnsIncludingImagesAndHistory() throws {
        let earlier = AITurn(role: .assistant, contentJSON: try JSONSerialization.data(withJSONObject: [
            ["type": "thinking", "thinking": "private"], ["type": "text", "text": "Earlier answer"],
        ]))
        let messages = LocalProvider.messages(system: "S", turns: [
            .user([.text("First")]), earlier, .user([.jpeg(Data([0xFF])), .text("Look at this")]),
        ])
        #expect(messages.count == 4)
        #expect(messages[2]["content"] as? String == "Earlier answer")
        #expect((messages[3]["content"] as? String)?.hasPrefix("[An image was attached") == true)
        #expect((messages[3]["content"] as? String)?.hasSuffix("Look at this") == true)
    }

    @Test func routesByModel() {
        let settings = AISettings()
        #expect(settings.provider(for: ModelCatalog.localID) is LocalProvider)
        #expect(settings.provider(for: "claude-opus-5-5") is ClaudeProvider)
        #expect(settings.isAvailable(ModelCatalog.localID))
    }
}

/// Talks to a real mlx_lm.server. Runs only when one is given:
///   TEST_RUNNER_GENBOARD_LOCAL_URL=http://127.0.0.1:8080 tools/test.sh LiveLocalModelTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GENBOARD_LOCAL_URL"] != nil))
struct LiveLocalModelTests {
    private var provider: LocalProvider {
        LocalProvider(baseURL: URL(string: ProcessInfo.processInfo.environment["GENBOARD_LOCAL_URL"]!)!, modelName: "")
    }

    @Test func answersAQuestion() async throws {
        let models = try await provider.availableModels()
        #expect(!models.isEmpty)
        let reply = try await provider.send(model: ModelCatalog.localID, effort: "low", system: Prompts.assistant,
                                            turns: [.user([.text("In one sentence: what is a baptism record?")])], jsonSchema: nil)
        print("Local answer:", reply.text)
        #expect(!reply.text.isEmpty)
    }

    @Test func draftsASummaryAsJSON() async throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["where_left_off": ["type": "string"], "next_steps": ["type": "array", "items": ["type": "string"]],
                           "open_questions": ["type": "array", "items": ["type": "string"]]],
            "required": ["where_left_off", "next_steps", "open_questions"],
        ]
        let reply = try await provider.send(model: ModelCatalog.localID, effort: "low", system: Prompts.summary,
                                            turns: [.user([.text("Pages: [PINNED] Baptism of Émilie Tremblay 1861, names father Antoine. [DEAD END] 1861 census search. Draft the end-of-session note.")])],
                                            jsonSchema: schema)
        print("Local JSON:", reply.text)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(reply.text.utf8)) as? [String: Any])
        #expect(json["where_left_off"] is String)
    }
}
