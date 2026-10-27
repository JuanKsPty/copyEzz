import Foundation
import Testing
@testable import CopyEzzCore

private let png = Data([0x89, 0x50, 0x4E, 0x47])

private func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct ClaudeCodeBackendTests {
    @Test func usesHeadlessFlags() {
        let arguments = ClaudeCodeBackend.arguments(model: "haiku")
        #expect(arguments.starts(with: ["-p", "--input-format", "stream-json"]))
        #expect(arguments.contains("--strict-mcp-config"))
        let model = arguments.firstIndex(of: "--model")
        #expect(model.map { arguments[$0 + 1] } == "haiku")
        #expect(arguments.contains(Prompt.system))
    }

    @Test func passesContextPromptAsFile() {
        let file = URL(filePath: "/tmp/prompt.txt")
        let arguments = ClaudeCodeBackend.arguments(model: "haiku", systemPromptFile: file)
        #expect(!arguments.contains("--system-prompt"))
        let flag = arguments.firstIndex(of: "--system-prompt-file")
        #expect(flag.map { arguments[$0 + 1] } == "/tmp/prompt.txt")
        #expect(arguments.contains("--strict-mcp-config"))
    }

    @Test func sendsImageAsStreamJSONLine() throws {
        let line = try ClaudeCodeBackend.stdinLine(png: png)
        #expect(line.last == UInt8(ascii: "\n"))
        let message = try json(line)
        #expect(message["type"] as? String == "user")
        let content = try #require((message["message"] as? [String: Any])?["content"] as? [[String: Any]])
        let source = try #require(content.first?["source"] as? [String: Any])
        #expect(source["data"] as? String == png.base64EncodedString())
        #expect(content.last?["text"] as? String == Prompt.userText)
    }

    @Test func readsLastResultEvent() throws {
        let stdout = """
            {"type":"system","subtype":"init"}
            {"type":"result","is_error":false,"result":"b) TO_DATE\\nConvierte texto a fecha."}
            """
        #expect(try ClaudeCodeBackend.parseResult(stdout: stdout, stderr: "", status: 0) == "b) TO_DATE\nConvierte texto a fecha.")
    }

    @Test func reportsErrors() {
        let failed = #"{"type":"result","is_error":true,"result":"Not logged in"}"#
        #expect(throws: CopyEzzError("Not logged in")) {
            try ClaudeCodeBackend.parseResult(stdout: failed, stderr: "", status: 1)
        }
        #expect(throws: CopyEzzError("boom")) {
            try ClaudeCodeBackend.parseResult(stdout: "", stderr: "boom\n", status: 1)
        }
        #expect(throws: CopyEzzError("claude salió con código 2")) {
            try ClaudeCodeBackend.parseResult(stdout: "", stderr: "", status: 2)
        }
    }
}

@Suite struct AnthropicAPIBackendTests {
    @Test func opusUsesLowEffortAndFallbacks() throws {
        let request = try AnthropicAPIBackend.makeRequest(
            baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "test", png: png, model: "claude-opus-5-5")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == AnthropicAPIBackend.fallbackBeta)
        let body = try json(try #require(request.httpBody))
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(body["system"] as? String == Prompt.system)
    }

    @Test func haikuSkipsEffortAndFallbacks() throws {
        let request = try AnthropicAPIBackend.makeRequest(
            baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "test", png: png, model: "claude-haiku-4-5")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let body = try json(try #require(request.httpBody))
        #expect(body["fallbacks"] == nil)
        #expect(body["output_config"] == nil)
    }

    @Test func cachesSystemPromptWithContext() throws {
        let request = try AnthropicAPIBackend.makeRequest(
            baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "test", png: png, model: "claude-opus-5-5",
            context: "TO_DATE convierte texto a fecha.")
        let body = try json(try #require(request.httpBody))
        let system = try #require(body["system"] as? [[String: Any]])
        #expect(system.count == 1)
        #expect(system[0]["text"] as? String == Prompt.system(context: "TO_DATE convierte texto a fecha."))
        #expect((system[0]["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
    }

    @Test func joinsTextBlocks() throws {
        let response = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"b) TO_DATE"},{"type":"text","text":"\nporque sí"}]}"#
        #expect(try AnthropicAPIBackend.parseResponse(data: Data(response.utf8), status: 200) == "b) TO_DATE\nporque sí")
    }

    @Test func mapsErrors() {
        let refusal = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        #expect(throws: CopyEzzError("el modelo rechazó la solicitud")) {
            try AnthropicAPIBackend.parseResponse(data: refusal, status: 200)
        }
        #expect(throws: CopyEzzError("API key inválida")) {
            try AnthropicAPIBackend.parseResponse(data: Data(), status: 401)
        }
        let badRequest = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad image"}}"#.utf8)
        #expect(throws: CopyEzzError("API 400: bad image")) {
            try AnthropicAPIBackend.parseResponse(data: badRequest, status: 400)
        }
    }

    @Test func requiresAPIKey() async {
        await #expect(throws: CopyEzzError("falta ANTHROPIC_API_KEY")) {
            try await AnthropicAPIBackend(apiKey: nil).solve(png: png, model: "claude-opus-5-5", context: nil)
        }
    }
}

@Suite struct OllamaBackendTests {
    @Test func buildsChatRequest() throws {
        let body = OllamaBackend.requestBody(png: png, model: "qwen2.5vl:7b")
        #expect(body["keep_alive"] as? String == "30m")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["content"] as? String == Prompt.system)
        #expect((messages.last?["images"] as? [String])?.first == png.base64EncodedString())
        #expect((body["options"] as? [String: Any])?["num_ctx"] == nil)
    }

    @Test func growsWindowForContext() throws {
        let context = String(repeating: "a", count: 300_000)
        let body = OllamaBackend.requestBody(png: png, model: "qwen2.5vl:7b", context: context)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["content"] as? String == Prompt.system(context: context))
        #expect((body["options"] as? [String: Any])?["num_ctx"] as? Int == 106_496)  // 100 mil + 4096, redondeado
        #expect(OllamaBackend.contextLength(for: "corto") == 8192)
    }

    @Test func parsesResponse() throws {
        let ok = Data(#"{"message":{"role":"assistant","content":"b) TO_DATE"}}"#.utf8)
        #expect(try OllamaBackend.parseResponse(data: ok, status: 200) == "b) TO_DATE")
        let missing = Data(#"{"error":"model 'x' not found"}"#.utf8)
        #expect(throws: CopyEzzError("Ollama: model 'x' not found")) {
            try OllamaBackend.parseResponse(data: missing, status: 404)
        }
    }
}
