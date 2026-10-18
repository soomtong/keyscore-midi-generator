import Foundation

enum OpenRouterError: LocalizedError {
    case missingKey
    case http(Int, String)
    case emptyResponse
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "OpenRouter API key 가 없습니다. 환경변수 OPENROUTER_API_KEY 또는 설정에서 입력하세요."
        case .http(let code, let body): return "OpenRouter HTTP \(code): \(body.prefix(300))"
        case .emptyResponse: return "OpenRouter 응답이 비어 있습니다."
        case .badJSON(let why): return "생성 결과를 해석하지 못했습니다: \(why)"
        }
    }
}

struct OpenRouterClient {
    var apiKey: String
    var model: String

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenRouterError.missingKey }
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 240
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("KeyScore MIDI Generator", forHTTPHeaderField: "X-Title")
        let body: [String: Any] = [
            "model": model,
            "temperature": 1.0,
            "max_tokens": 12000,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let msg = choices.first?["message"] as? [String: Any],
            let content = msg["content"] as? String, !content.isEmpty
        else { throw OpenRouterError.emptyResponse }
        return content
    }
}
