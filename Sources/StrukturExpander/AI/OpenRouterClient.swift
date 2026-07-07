import Foundation

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case badResponse(status: Int, body: String)
    case emptyCompletion

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenRouter API key configured (Settings → AI)"
        case .badResponse(let status, let body):
            return "OpenRouter returned HTTP \(status): \(String(body.prefix(200)))"
        case .emptyCompletion:
            return "OpenRouter returned an empty completion"
        }
    }
}

/// Minimal OpenRouter chat-completions client used by the AI assistant
/// and the %ai:% snippet macro.
final class OpenRouterClient {
    static let shared = OpenRouterClient()

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    struct Message: Codable {
        let role: String
        let content: String
    }

    private struct RequestBody: Codable {
        let model: String
        let messages: [Message]
        let max_tokens: Int
        let temperature: Double
    }

    private struct ResponseBody: Codable {
        struct Choice: Codable {
            struct ChoiceMessage: Codable { let content: String? }
            let message: ChoiceMessage
        }
        let choices: [Choice]
    }

    private struct ErrorBody: Codable {
        struct APIError: Codable { let message: String? }
        let error: APIError?
    }

    /// One-shot completion used by the %ai:% macro: the prompt result is
    /// inserted verbatim, so the system prompt demands bare output.
    func complete(prompt: String, maxTokens: Int = 1024) async throws -> String {
        try await chat(messages: [
            Message(role: "system", content:
                "You are a text-expansion assistant. Reply with ONLY the text to insert — no preamble, no quotes, no markdown fences, no explanations."),
            Message(role: "user", content: prompt),
        ], maxTokens: maxTokens)
    }

    /// General chat call used by the snippet AI assistant.
    func chat(messages: [Message], maxTokens: Int = 2048, temperature: Double = 0.7) async throws -> String {
        let settings = AppSettings.shared
        let apiKey = settings.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw OpenRouterError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/strukturunion-mmw/strukturunion-textexpander", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("StrukturExpander", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: settings.openRouterModel,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let apiMessage = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
            throw OpenRouterError.badResponse(status: status, body: apiMessage ?? String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.isEmpty else {
            throw OpenRouterError.emptyCompletion
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quick connectivity check for the Settings pane.
    func test() async -> Result<String, Error> {
        do {
            let reply = try await complete(prompt: "Reply with the single word: OK", maxTokens: 10)
            return .success(reply)
        } catch {
            return .failure(error)
        }
    }
}
