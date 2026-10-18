import Foundation

enum OpenRouterError: LocalizedError {
    case missingKey
    case http(Int, String)
    case api(String)
    case emptyResponse
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "OpenRouter API key 가 없습니다. 환경변수 OPENROUTER_API_KEY 또는 설정에서 입력하세요."
        case .http(let code, let body): return "OpenRouter HTTP \(code): \(body.prefix(300))"
        case .api(let message): return "OpenRouter 오류: \(message.prefix(300))"
        case .emptyResponse: return "OpenRouter 응답이 비어 있습니다."
        case .badJSON(let why): return "생성 결과를 해석하지 못했습니다: \(why)"
        }
    }
}

/// OpenRouter chat completions 호출. 값 타입이라 Task 경계를 넘겨도 안전하다.
struct OpenRouterClient: Sendable {
    var apiKey: String
    var model: String
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private struct Request: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        struct ResponseFormat: Encodable {
            var type: String
        }
        var model: String
        var temperature: Double
        var maxTokens: Int
        var responseFormat: ResponseFormat
        var messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, temperature, messages
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }
            var message: Message
        }
        struct APIError: Decodable {
            var message: String
        }
        var choices: [Choice]?
        var error: APIError?
    }

    /// 호출 중인 Task 가 취소되면 URLSession 이 CancellationError 로 끝난다.
    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenRouterError.missingKey }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 240
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("KeyScore MIDI Generator", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONEncoder().encode(Request(
            model: model, temperature: 1.0, maxTokens: 12000, responseFormat: .init(type: "json_object"),
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)]))
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        let parsed: Response
        do { parsed = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw OpenRouterError.badJSON("응답 형식이 다릅니다 (\(error.localizedDescription))")
        }
        // OpenRouter 는 200 으로도 {"error": ...} 를 돌려줄 때가 있다
        if let apiError = parsed.error { throw OpenRouterError.api(apiError.message) }
        guard let content = parsed.choices?.first?.message.content, !content.isEmpty else {
            throw OpenRouterError.emptyResponse
        }
        return content
    }
}
