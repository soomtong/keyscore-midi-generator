import Foundation

struct ModelPreset: Identifiable, Hashable {
    let id: String
    let name: String
    /// 1M 토큰당 입력/출력 USD
    let price: String
    let note: String

    var label: String { "\(name) · \(price)" }
}

/// OpenRouter /api/v1/models 로 ID 와 가격을 확인하고 실제 곡 생성 호출까지 검증한 저가 모델 (2026-10-18).
enum ModelCatalog {
    static let presets: [ModelPreset] = [
        ModelPreset(id: "anthropic/claude-haiku-5.5", name: "Claude Haiku 5.5", price: "$0.10 / $0.50", note: "빠름 (약 15초), JSON 안정적"),
        ModelPreset(id: "openai/gpt-6-luna", name: "GPT-6 Luna", price: "$0.10 / $0.50", note: "빠름 (약 20초)"),
        ModelPreset(id: "deepseek/deepseek-v4.1-flash", name: "DeepSeek V4.1 Flash", price: "$0.065 / $0.144", note: "오픈 가중치, 가장 저렴하면서 빠름 (약 25초)"),
        ModelPreset(id: "z-ai/glm-5.3-flash", name: "GLM 5.3 Flash", price: "$0.048 / $0.20", note: "오픈 가중치 (약 1분)"),
        ModelPreset(id: "qwen/qwen3.8-flash", name: "Qwen3.8 Flash", price: "$0.15 / $0.47", note: "오픈 가중치, 생각 시간이 길어 느림 (약 1.5분)"),
    ]

    static let defaultID = presets[0].id
    private static let defaultsKey = "openrouter.model"

    /// 환경변수 OPENROUTER_MODEL > 마지막 선택 > 기본값
    static func initial() -> String {
        ProcessInfo.processInfo.environment["OPENROUTER_MODEL"]
            ?? UserDefaults.standard.string(forKey: defaultsKey)
            ?? defaultID
    }

    static func save(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultsKey)
    }

    static func preset(for id: String) -> ModelPreset? {
        presets.first { $0.id == id }
    }
}
