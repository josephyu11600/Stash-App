import Foundation

/// Minimal Anthropic Messages API client. Knows nothing about Stash — callers describe a tool
/// and get back that tool's input as the structured result.
enum ClaudeAPI {
    struct Tool {
        let name: String
        let description: String
        let schema: [String: Any]
    }

    enum Failure: LocalizedError {
        case missingKey
        case http(Int, String)
        case malformed
        case noToolCall

        var errorDescription: String? {
            switch self {
            case .missingKey: "Missing CLAUDE_API_KEY in Stash/Secrets.plist."
            case .http(let code, let body): "HTTP \(code): \(body.prefix(400))"
            case .malformed: "Malformed API response."
            case .noToolCall: "Model never called the requested tool."
            }
        }
    }

    /// Sends one user turn and returns the input the model passed to `tool`.
    /// With `webSearchUses > 0` the model may search first; server-side search runs inside the
    /// request, and `pause_turn` responses are resumed automatically.
    static func callTool(
        model: String,
        system: String,
        content: [[String: Any]],
        tool: Tool,
        webSearchUses: Int = 0,
        maxTokens: Int = 2048
    ) async throws -> [String: Any] {
        var tools: [[String: Any]] = [
            ["name": tool.name, "description": tool.description, "input_schema": tool.schema]
        ]
        if webSearchUses > 0 {
            tools.append(["type": "web_search_20250305", "name": "web_search", "max_uses": webSearchUses])
        }
        // Always "auto": newer models (e.g. Sonnet 5.5) reject forced tool choice, and forcing
        // would also skip web search. The system prompt says to finish with the tool, and the
        // loop below nudges the model if it answers in prose instead.
        var messages: [[String: Any]] = [["role": "user", "content": content]]

        for _ in 0..<4 {
            let response = try await send([
                "model": model,
                "max_tokens": maxTokens,
                "system": system,
                "tools": tools,
                "tool_choice": ["type": "auto"],
                "messages": messages
            ])
            guard let blocks = response["content"] as? [[String: Any]] else { throw Failure.malformed }

            if let call = blocks.first(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == tool.name }),
               let input = call["input"] as? [String: Any] {
                return input
            }

            messages.append(["role": "assistant", "content": blocks])
            if response["stop_reason"] as? String != "pause_turn" {
                // Model answered in prose instead of calling the tool; ask again.
                messages.append(["role": "user", "content": "Call \(tool.name) now with your final answer."])
            }
        }
        throw Failure.noToolCall
    }

    private static func send(_ body: [String: Any]) async throws -> [String: Any] {
        let key = Config.claudeAPIKey
        guard !key.isEmpty else { throw Failure.missingKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformed
        }
        return json
    }

    // MARK: - Content helpers

    static func text(_ s: String) -> [String: Any] {
        ["type": "text", "text": s]
    }

    static func jpeg(_ data: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
    }

    /// Model output occasionally leaks markup or search citation markers into string fields.
    static func plainText(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]{0,200}>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\[[\\d,\\s]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
