import Foundation

/// LLM이 출력하는 플러그인 사양 JSON 구조
struct LLMPluginSpec: Codable {
    let id: String?
    let name: String
    let description: String
    let icon: String?
    let handlers: Handlers?
    let config: [ConfigFieldSpec]?
    let capabilities: CapabilitiesSpec?

    struct Handlers: Codable {
        let onMessage: ActionSpec?
        let onRoomCreated: ActionSpec?
        let onRoomCompleted: ActionSpec?
        let onRoomFailed: ActionSpec?

        enum CodingKeys: String, CodingKey {
            case onMessage = "on_message"
            case onRoomCreated = "on_room_created"
            case onRoomCompleted = "on_room_completed"
            case onRoomFailed = "on_room_failed"
        }
    }

    struct ActionSpec: Codable {
        let action: String   // "webhook", "shell", "notification"
        let url: String?
        let command: String?
        let title: String?
        let body: String?
    }

    struct ConfigFieldSpec: Codable {
        let key: String
        let label: String
        let secret: Bool?
        let placeholder: String?
    }

    struct CapabilitiesSpec: Codable {
        let skillTags: [String]?
        let rules: [String]?
        let workModes: [String]?
    }
}

// MARK: - 에러

enum LLMPluginBuilderError: Error, LocalizedError {
    case emptyName
    case noHandlers
    case invalidActionType(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:               return "플러그인 이름이 비어있습니다"
        case .noHandlers:              return "최소 1개의 핸들러가 필요합니다"
        case .invalidActionType(let t): return "지원하지 않는 액션 타입: \(t)"
        }
    }
}
