import Foundation

// MARK: - 플러그인 프리셋

/// 원클릭 설치 가능한 플러그인 프리셋 (AgentPreset 패턴)
struct PluginPreset: Identifiable {
    let id: String
    let name: String
    let icon: String               // SF Symbol
    let category: PresetCategory
    let description: String
    let tags: [String]             // 이 프리셋이 제공하는 skillTags 미리보기

    // 설치 시 생성되는 manifest 데이터
    let globalConfigFields: [PluginManifest.ManifestConfigField]
    let agentConfigFields: [PluginManifest.ManifestConfigField]
    let capabilities: PluginManifest.ManifestCapabilities
    let handlers: PluginManifest.PluginHandlers
    let scripts: [(filename: String, content: String)]

    enum PresetCategory: String, CaseIterable {
        case communication       // 커뮤니케이션
        case projectManagement   // 프로젝트 관리
        case development         // 개발

        var displayName: String {
            switch self {
            case .communication: return "커뮤니케이션"
            case .projectManagement: return "프로젝트 관리"
            case .development: return "개발"
            }
        }
    }

    /// 프리셋 → PluginManifest 변환
    func toManifest() -> PluginManifest {
        PluginManifest(
            id: id,
            name: name,
            description: description,
            version: "1.0.0",
            icon: icon,
            author: "DOUGLAS",
            handlers: handlers,
            config: globalConfigFields.isEmpty ? nil : globalConfigFields,
            agentConfig: agentConfigFields.isEmpty ? nil : agentConfigFields,
            capabilities: capabilities
        )
    }
}

// MARK: - 빌트인 프리셋 3종

extension PluginPreset {
    static let builtIn: [PluginPreset] = [slackMonitor, jiraManager, webhookNotify]

    // MARK: 1. Slack 모니터

    static let slackMonitor = PluginPreset(
        id: "slack-monitor",
        name: "Slack 모니터",
        icon: "bubble.left.and.bubble.right",
        category: .communication,
        description: "슬랙 채널 메시지를 감시하여 DOUGLAS 워크플로우로 전달합니다.",
        tags: ["slack", "실시간 알림", "메시지 모니터링"],
        globalConfigFields: [
            .init(key: "botToken", label: "Bot Token (xoxb-)", secret: true, placeholder: "xoxb-..."),
            .init(key: "appToken", label: "App-Level Token (xapp-)", secret: true, placeholder: "xapp-..."),
        ],
        agentConfigFields: [
            .init(key: "channelFilter", label: "채널 필터 (빈칸=전체)", secret: nil, placeholder: "#backend, #bugs"),
            .init(key: "triggerPatterns", label: "트리거 패턴 (쉼표 구분)", secret: nil, placeholder: "@douglas, !ask"),
        ],
        capabilities: .init(
            skillTags: ["slack", "실시간 알림", "메시지 모니터링", "채널"],
            rules: [
                "슬랙 메시지를 수신하면 해당 스레드에 분석 결과를 답장하세요.",
                "슬랙 메시지의 맥락(채널, 스레드)을 항상 보존하세요.",
            ],
            workModes: ["execute", "research"]
        ),
        handlers: .init(
            onMessage: "on_message.sh",
            onRoomCreated: nil,
            onRoomCompleted: "on_room_completed.sh",
            onRoomFailed: nil,
            onActivate: nil,
            onDeactivate: nil
        ),
        scripts: [
            ("on_message.sh", """
            #!/bin/bash
            # Slack 메시지 수신 시 처리
            # 환경변수: ROOM_ID, MESSAGE_ROLE, MESSAGE_CONTENT, MESSAGE_AGENT
            echo '{"type": "reply", "text": "메시지를 분석하고 있습니다..."}'
            """),
            ("on_room_completed.sh", """
            #!/bin/bash
            # 방 완료 시 Slack 알림
            # 환경변수: ROOM_ID, ROOM_TITLE
            if [ -n "$PLUGIN_botToken" ] && [ -n "$PLUGIN_channelFilter" ]; then
                curl -s -X POST "https://slack.com/api/chat.postMessage" \\
                    -H "Authorization: Bearer $PLUGIN_botToken" \\
                    -H "Content-Type: application/json" \\
                    -d "{\"channel\": \"$PLUGIN_channelFilter\", \"text\": \"✅ $ROOM_TITLE 완료\"}" > /dev/null
            fi
            """),
        ]
    )

    // MARK: 2. Jira 관리자

    static let jiraManager = PluginPreset(
        id: "jira-manager",
        name: "Jira 관리자",
        icon: "list.bullet.clipboard",
        category: .projectManagement,
        description: "Jira 티켓 작업 시 자동 할당, 상태 변경, 코멘트를 관리합니다.",
        tags: ["jira", "티켓 관리", "작업 추적"],
        globalConfigFields: [],  // JiraConfig 싱글턴 사용
        agentConfigFields: [
            .init(key: "autoAssign", label: "작업 시작 시 자동 할당", secret: nil, placeholder: "true / false"),
            .init(key: "commentOnStart", label: "작업 시작 코멘트", secret: nil, placeholder: "DOUGLAS가 분석 중입니다"),
        ],
        capabilities: .init(
            skillTags: ["jira", "티켓 관리", "작업 추적", "프로젝트 관리"],
            rules: [
                "Jira 티켓을 분석할 때 이슈 타입(Bug, Story, Task)에 따라 접근 방식을 다르게 하세요.",
                "작업 완료 시 결과를 Jira 코멘트로 남기세요.",
            ],
            workModes: ["execute", "research"]
        ),
        handlers: .init(
            onMessage: nil,
            onRoomCreated: nil,
            onRoomCompleted: "on_room_completed.sh",
            onRoomFailed: "on_room_failed.sh",
            onActivate: nil,
            onDeactivate: nil
        ),
        scripts: [
            ("on_room_completed.sh", """
            #!/bin/bash
            # 방 완료 시 Jira 코멘트 추가
            # DOUGLAS의 Jira 도구(jira_add_comment)를 통해 처리됨
            echo "Room $ROOM_ID completed: $ROOM_TITLE"
            """),
            ("on_room_failed.sh", """
            #!/bin/bash
            # 방 실패 시 로깅
            echo "Room $ROOM_ID failed: $ROOM_TITLE"
            """),
        ]
    )

    // MARK: 3. Webhook 알림

    static let webhookNotify = PluginPreset(
        id: "webhook-notify",
        name: "Webhook 알림",
        icon: "bell.badge",
        category: .communication,
        description: "방 완료/실패 시 외부 서비스에 웹훅 알림을 전송합니다.",
        tags: ["webhook", "알림", "외부 연동"],
        globalConfigFields: [
            .init(key: "webhookURL", label: "Webhook URL", secret: nil, placeholder: "https://hooks.example.com/..."),
        ],
        agentConfigFields: [
            .init(key: "eventFilter", label: "알림 이벤트 (쉼표 구분)", secret: nil, placeholder: "completed, failed"),
        ],
        capabilities: .init(
            skillTags: ["webhook", "알림", "외부 연동"],
            rules: [
                "작업 결과를 외부 시스템에 알림으로 전달하세요.",
            ],
            workModes: ["execute"]
        ),
        handlers: .init(
            onMessage: nil,
            onRoomCreated: nil,
            onRoomCompleted: "on_room_completed.sh",
            onRoomFailed: "on_room_failed.sh",
            onActivate: nil,
            onDeactivate: nil
        ),
        scripts: [
            ("on_room_completed.sh", """
            #!/bin/bash
            # 방 완료 시 웹훅 전송
            if [ -n "$PLUGIN_webhookURL" ]; then
                curl -s -X POST "$PLUGIN_webhookURL" \\
                    -H "Content-Type: application/json" \\
                    -d "{\"event\": \"completed\", \"room_id\": \"$ROOM_ID\", \"title\": \"$ROOM_TITLE\"}" > /dev/null
            fi
            """),
            ("on_room_failed.sh", """
            #!/bin/bash
            # 방 실패 시 웹훅 전송
            if [ -n "$PLUGIN_webhookURL" ]; then
                curl -s -X POST "$PLUGIN_webhookURL" \\
                    -H "Content-Type: application/json" \\
                    -d "{\"event\": \"failed\", \"room_id\": \"$ROOM_ID\", \"title\": \"$ROOM_TITLE\"}" > /dev/null
            fi
            """),
        ]
    )
}
