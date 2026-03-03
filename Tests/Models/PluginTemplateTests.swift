import Testing
import Foundation
@testable import DOUGLAS

@Suite("PluginTemplate Tests")
struct PluginTemplateTests {

    // MARK: - PluginSlug

    @Test("한국어 이름 슬러그 생성")
    func koreanSlug() {
        let slug = PluginSlug.generate(from: "웹훅 알림")
        #expect(slug.hasPrefix("custom-"))
        #expect(!slug.contains(" "))
        // ASCII만 포함
        #expect(slug.allSatisfy { $0.isASCII })
        // 4자리 랜덤 접미어
        let parts = slug.split(separator: "-")
        #expect(parts.count >= 3)
    }

    @Test("ASCII 이름 슬러그 생성")
    func asciiSlug() {
        let slug = PluginSlug.generate(from: "My Webhook")
        #expect(slug.hasPrefix("custom-"))
        #expect(slug.contains("my"))
        #expect(slug.contains("webhook"))
    }

    @Test("빈 이름 슬러그")
    func emptySlug() {
        let slug = PluginSlug.generate(from: "")
        #expect(slug.hasPrefix("custom-plugin-"))
    }

    @Test("특수문자 이름 슬러그")
    func specialCharSlug() {
        let slug = PluginSlug.generate(from: "!@#$%")
        #expect(slug.hasPrefix("custom-"))
        #expect(slug.allSatisfy { $0.isASCII })
    }

    @Test("슬러그 고유성 — 같은 이름에서 다른 결과")
    func slugUniqueness() {
        let slug1 = PluginSlug.generate(from: "테스트")
        let slug2 = PluginSlug.generate(from: "테스트")
        // 랜덤 접미어로 인해 매우 높은 확률로 다름 (1/1,679,616)
        // 테스트 안정성을 위해 여러 번 생성하여 최소 1개는 다른지 확인
        let slugs = (0..<5).map { _ in PluginSlug.generate(from: "테스트") }
        let uniqueCount = Set(slugs).count
        #expect(uniqueCount > 1)
    }

    // MARK: - ScriptGenerator

    @Test("웹훅 스크립트 생성")
    func webhookScript() {
        let handler = HandlerConfig(
            eventType: .onRoomCompleted,
            actionType: .webhook,
            webhookURL: "https://example.com/hook"
        )
        let script = ScriptGenerator.generate(handler: handler)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("curl"))
        #expect(script.contains("https://example.com/hook"))
        #expect(script.contains("DOUGLAS_ROOM_ID"))
    }

    @Test("쉘 명령 스크립트 생성")
    func shellScript() {
        var handler = HandlerConfig(eventType: .onMessage)
        handler.actionType = .shell
        handler.shellCommand = "echo \"hello\" >> ~/log.txt"
        let script = ScriptGenerator.generate(handler: handler)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("echo \"hello\" >> ~/log.txt"))
    }

    @Test("macOS 알림 스크립트 생성")
    func notificationScript() {
        var handler = HandlerConfig(eventType: .onRoomCompleted)
        handler.actionType = .notification
        handler.notifTitle = "완료!"
        handler.notifBody = "작업이 끝났습니다"
        let script = ScriptGenerator.generate(handler: handler)
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("osascript"))
        #expect(script.contains("완료!"))
        #expect(script.contains("작업이 끝났습니다"))
    }

    @Test("빈 URL 웹훅 → 기본값 사용")
    func webhookDefaultURL() {
        let handler = HandlerConfig(
            eventType: .onRoomCreated,
            actionType: .webhook,
            webhookURL: ""
        )
        let script = ScriptGenerator.generate(handler: handler)
        #expect(script.contains("https://example.com/webhook"))
    }

    // MARK: - 매니페스트 생성

    @Test("매니페스트 생성 — 기본")
    func manifestGeneration() {
        let handlers = [
            HandlerConfig(eventType: .onMessage, actionType: .webhook, webhookURL: "https://hook.test"),
            HandlerConfig(eventType: .onRoomCompleted, actionType: .notification, notifTitle: "완료"),
        ]
        let configFields = [
            BuilderConfigField(key: "api_key", label: "API Key", isSecret: true, placeholder: "sk-..."),
        ]

        let manifest = ScriptGenerator.generateManifest(
            id: "custom-test-1234",
            name: "테스트 플러그인",
            description: "테스트용",
            icon: "bell.badge",
            handlers: handlers,
            configFields: configFields
        )

        #expect(manifest.id == "custom-test-1234")
        #expect(manifest.name == "테스트 플러그인")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.icon == "bell.badge")
        #expect(manifest.handlers?.onMessage == "on_message.sh")
        #expect(manifest.handlers?.onRoomCompleted == "on_room_completed.sh")
        #expect(manifest.handlers?.onRoomCreated == nil)
        #expect(manifest.handlers?.onRoomFailed == nil)
        #expect(manifest.config?.count == 1)
        #expect(manifest.config?[0].key == "api_key")
        #expect(manifest.config?[0].secret == true)
    }

    @Test("매니페스트 JSON 라운드트립")
    func manifestRoundTrip() throws {
        let handlers = [
            HandlerConfig(eventType: .onRoomFailed, actionType: .shell, shellCommand: "echo fail"),
        ]

        let manifest = ScriptGenerator.generateManifest(
            id: "custom-roundtrip-abcd",
            name: "라운드트립",
            description: "테스트",
            icon: "gear",
            handlers: handlers,
            configFields: []
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PluginManifest.self, from: data)

        #expect(decoded.id == manifest.id)
        #expect(decoded.name == manifest.name)
        #expect(decoded.handlers?.onRoomFailed == "on_room_failed.sh")
        #expect(decoded.config == nil) // 빈 배열 → nil
    }

    @Test("빈 설정 필드는 매니페스트에서 제외")
    func emptyConfigFieldsExcluded() {
        let configFields = [
            BuilderConfigField(key: "", label: "", isSecret: false, placeholder: ""),
        ]

        let manifest = ScriptGenerator.generateManifest(
            id: "test-id",
            name: "test",
            description: "desc",
            icon: "gear",
            handlers: [HandlerConfig(eventType: .onMessage, actionType: .webhook, webhookURL: "https://x.com")],
            configFields: configFields
        )

        #expect(manifest.config == nil)
    }

    // MARK: - PluginEventType

    @Test("이벤트 타입 속성")
    func eventTypeProperties() {
        #expect(PluginEventType.onMessage.handlerKey == "on_message")
        #expect(PluginEventType.onMessage.scriptFileName == "on_message.sh")
        #expect(PluginEventType.onRoomCreated.handlerKey == "on_room_created")
        #expect(PluginEventType.onRoomCompleted.handlerKey == "on_room_completed")
        #expect(PluginEventType.onRoomFailed.handlerKey == "on_room_failed")
    }

    @Test("메시지 이벤트 변수 목록")
    func messageEventVariables() {
        let vars = PluginEventType.onMessage.availableVariables
        #expect(vars.contains("$DOUGLAS_MESSAGE_CONTENT"))
        #expect(vars.contains("$DOUGLAS_ROOM_ID"))
        #expect(vars.contains("$DOUGLAS_MESSAGE_ROLE"))
    }

    @Test("방 이벤트 변수 목록")
    func roomEventVariables() {
        let vars = PluginEventType.onRoomCompleted.availableVariables
        #expect(vars.contains("$DOUGLAS_ROOM_ID"))
        #expect(vars.contains("$DOUGLAS_ROOM_TITLE"))
        #expect(!vars.contains("$DOUGLAS_MESSAGE_CONTENT"))
    }

    // MARK: - PluginActionType

    @Test("액션 타입 allCases 3종")
    func actionTypeCount() {
        #expect(PluginActionType.allCases.count == 3)
    }

    @Test("액션 타입 displayName")
    func actionTypeDisplayNames() {
        #expect(PluginActionType.webhook.displayName == "웹훅 전송")
        #expect(PluginActionType.shell.displayName == "쉘 명령")
        #expect(PluginActionType.notification.displayName == "macOS 알림")
    }
}
