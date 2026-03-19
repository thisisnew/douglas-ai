import Foundation

// MARK: - 플러그인 액션 타입 (노코드 빌더용)

/// 빌더에서 선택 가능한 액션 유형
enum PluginActionType: String, CaseIterable, Identifiable {
    case webhook       // 웹훅 전송
    case shell         // 쉘 명령
    case notification  // macOS 알림

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .webhook:      return "웹훅 전송"
        case .shell:        return "쉘 명령"
        case .notification: return "macOS 알림"
        }
    }

    var icon: String {
        switch self {
        case .webhook:      return "arrow.up.forward.app"
        case .shell:        return "terminal"
        case .notification: return "bell.badge"
        }
    }

    var description: String {
        switch self {
        case .webhook:      return "URL로 JSON 데이터를 POST 전송"
        case .shell:        return "쉘 명령어를 실행"
        case .notification: return "macOS 시스템 알림 표시"
        }
    }
}

// MARK: - 플러그인 이벤트 타입

/// 빌더에서 선택 가능한 이벤트 유형 (on_activate/deactivate 제외 — 고급 기능)
enum PluginEventType: String, CaseIterable, Identifiable {
    case onMessage
    case onRoomCreated
    case onRoomCompleted
    case onRoomFailed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onMessage:       return "메시지 수신"
        case .onRoomCreated:   return "방 생성"
        case .onRoomCompleted: return "작업 완료"
        case .onRoomFailed:    return "작업 실패"
        }
    }

    var icon: String {
        switch self {
        case .onMessage:       return "bubble.left"
        case .onRoomCreated:   return "plus.rectangle"
        case .onRoomCompleted: return "checkmark.circle"
        case .onRoomFailed:    return "xmark.circle"
        }
    }

    /// plugin.json handlers 키 이름
    var handlerKey: String {
        switch self {
        case .onMessage:       return "on_message"
        case .onRoomCreated:   return "on_room_created"
        case .onRoomCompleted: return "on_room_completed"
        case .onRoomFailed:    return "on_room_failed"
        }
    }

    /// 생성될 스크립트 파일명
    var scriptFileName: String { "\(handlerKey).sh" }

    /// 이 이벤트에서 사용 가능한 DOUGLAS_* 환경 변수
    var availableVariables: [String] {
        switch self {
        case .onMessage:
            return [
                "$DOUGLAS_ROOM_ID",
                "$DOUGLAS_MESSAGE_ROLE",
                "$DOUGLAS_MESSAGE_CONTENT",
                "$DOUGLAS_MESSAGE_AGENT",
                "$DOUGLAS_MESSAGE_TYPE",
            ]
        case .onRoomCreated, .onRoomCompleted, .onRoomFailed:
            return [
                "$DOUGLAS_ROOM_ID",
                "$DOUGLAS_ROOM_TITLE",
            ]
        }
    }
}

// MARK: - 핸들러 설정

/// 이벤트 하나에 대한 액션 설정
struct HandlerConfig: Identifiable {
    let id = UUID()
    var eventType: PluginEventType
    var actionType: PluginActionType = .webhook

    // 웹훅
    var webhookURL: String = ""

    // 쉘 명령
    var shellCommand: String = ""

    // macOS 알림
    var notifTitle: String = ""
    var notifBody: String = ""
}

// MARK: - 사용자 설정 필드

/// 플러그인이 필요로 하는 사용자 입력 설정 (API Key, URL 등)
struct BuilderConfigField: Identifiable {
    let id = UUID()
    var key: String = ""
    var label: String = ""
    var isSecret: Bool = false
    var placeholder: String = ""
}

// MARK: - 슬러그 생성

/// 한국어 플러그인 이름 → ASCII 슬러그 변환
enum PluginSlug {
    /// "웹훅 알림" → "custom-webhug-allim-a1b2"
    static func generate(from name: String) -> String {
        let latinized = name
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? name

        let components = latinized.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let base = components.joined(separator: "-")
        let trimmed = String(base.prefix(30))

        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let suffix = String((0..<4).map { _ in chars.randomElement()! })

        return "custom-\(trimmed.isEmpty ? "plugin" : trimmed)-\(suffix)"
    }
}

// MARK: - 스크립트 생성

/// 핸들러 설정 → 쉘 스크립트 문자열 + 매니페스트 생성
enum ScriptGenerator {

    /// HandlerConfig → 스크립트 내용
    static func generate(handler: HandlerConfig) -> String {
        switch handler.actionType {
        case .webhook:
            return generateWebhook(handler: handler)
        case .shell:
            return generateShell(handler: handler)
        case .notification:
            return generateNotification(handler: handler)
        }
    }

    /// HandlerConfig 배열 + 메타데이터 → PluginManifest
    static func generateManifest(
        id: String,
        name: String,
        description: String,
        icon: String,
        handlers: [HandlerConfig],
        configFields: [BuilderConfigField]
    ) -> PluginManifest {
        // handlers → PluginHandlers 매핑
        var onMessage: String?
        var onRoomCreated: String?
        var onRoomCompleted: String?
        var onRoomFailed: String?

        for handler in handlers {
            let fileName = handler.eventType.scriptFileName
            switch handler.eventType {
            case .onMessage:       onMessage = fileName
            case .onRoomCreated:   onRoomCreated = fileName
            case .onRoomCompleted: onRoomCompleted = fileName
            case .onRoomFailed:    onRoomFailed = fileName
            }
        }

        let pluginHandlers = PluginManifest.PluginHandlers(
            onMessage: onMessage,
            onRoomCreated: onRoomCreated,
            onRoomCompleted: onRoomCompleted,
            onRoomFailed: onRoomFailed,
            onActivate: nil,
            onDeactivate: nil
        )

        // configFields → ManifestConfigField 매핑
        let manifestConfig = configFields
            .filter { !$0.key.isEmpty && !$0.label.isEmpty }
            .map { field in
                PluginManifest.ManifestConfigField(
                    key: field.key,
                    label: field.label,
                    secret: field.isSecret,
                    placeholder: field.placeholder.isEmpty ? nil : field.placeholder
                )
            }

        return PluginManifest(
            id: id,
            name: name,
            description: description,
            version: "1.0.0",
            icon: icon,
            author: nil,
            handlers: pluginHandlers,
            config: manifestConfig.isEmpty ? nil : manifestConfig,
            agentConfig: nil,
            capabilities: nil
        )
    }

    // MARK: - Private

    private static func generateWebhook(handler: HandlerConfig) -> String {
        let url = handler.webhookURL.isEmpty ? "https://example.com/webhook" : handler.webhookURL

        // 이벤트별 JSON 페이로드 구성
        let eventFields: String
        switch handler.eventType {
        case .onMessage:
            eventFields = """
              "room_id": "'"$DOUGLAS_ROOM_ID"'",
              "message_role": "'"$DOUGLAS_MESSAGE_ROLE"'",
              "message_content": "'"$DOUGLAS_MESSAGE_CONTENT"'",
              "message_agent": "'"$DOUGLAS_MESSAGE_AGENT"'"
            """
        case .onRoomCreated, .onRoomCompleted, .onRoomFailed:
            eventFields = """
              "room_id": "'"$DOUGLAS_ROOM_ID"'",
              "room_title": "'"$DOUGLAS_ROOM_TITLE"'"
            """
        }

        return """
        #!/bin/bash
        # 웹훅 전송 — \(handler.eventType.displayName)
        curl -s -X POST "\(url)" \\
          -H "Content-Type: application/json" \\
          -d '{
          "event": "\(handler.eventType.handlerKey)",
        \(eventFields)
        }' > /dev/null 2>&1
        """
    }

    private static func generateShell(handler: HandlerConfig) -> String {
        let command = handler.shellCommand.isEmpty ? "echo \"Event triggered\"" : handler.shellCommand
        return """
        #!/bin/bash
        # 쉘 명령 — \(handler.eventType.displayName)
        \(command)
        """
    }

    private static func generateNotification(handler: HandlerConfig) -> String {
        let title = handler.notifTitle.isEmpty ? "DOUGLAS" : handler.notifTitle
        let body = handler.notifBody.isEmpty ? "이벤트가 발생했습니다" : handler.notifBody
        return """
        #!/bin/bash
        # macOS 알림 — \(handler.eventType.displayName)
        osascript -e 'display notification "\(body)" with title "\(title)"'
        """
    }
}
