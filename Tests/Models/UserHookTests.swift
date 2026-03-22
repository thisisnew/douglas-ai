import Testing
import Foundation
@testable import DOUGLAS

@Suite("UserHook Tests")
struct UserHookTests {

    // MARK: - Codable 라운드트립

    @Test("UserHook Codable 라운드트립 — logToFile")
    func codableLogToFile() throws {
        let hook = UserHook(name: "이력 기록", trigger: .roomCompleted, action: .logToFile(path: "~/log.md"))
        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(UserHook.self, from: data)
        #expect(decoded.name == "이력 기록")
        #expect(decoded.trigger == .roomCompleted)
        #expect(decoded.isEnabled == true)
        if case .logToFile(let path) = decoded.action {
            #expect(path == "~/log.md")
        } else {
            Issue.record("Expected logToFile action")
        }
    }

    @Test("UserHook Codable 라운드트립 — runScript")
    func codableRunScript() throws {
        let hook = UserHook(name: "린트", trigger: .fileWritten, action: .runScript(path: "/usr/local/bin/lint.sh"))
        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(UserHook.self, from: data)
        #expect(decoded.trigger == .fileWritten)
        if case .runScript(let path) = decoded.action {
            #expect(path == "/usr/local/bin/lint.sh")
        } else {
            Issue.record("Expected runScript action")
        }
    }

    @Test("UserHook Codable 라운드트립 — systemNotification")
    func codableNotification() throws {
        let hook = UserHook(name: "알림", trigger: .approvalRequested, action: .systemNotification(title: "승인 필요"))
        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(UserHook.self, from: data)
        if case .systemNotification(let title) = decoded.action {
            #expect(title == "승인 필요")
        } else {
            Issue.record("Expected systemNotification action")
        }
    }

    // MARK: - HookTrigger

    @Test("HookTrigger CaseIterable — 5개 케이스")
    func triggerCount() {
        #expect(HookTrigger.allCases.count == 5)
    }

    @Test("HookTrigger displayName 비어있지 않음")
    func triggerDisplayNames() {
        for trigger in HookTrigger.allCases {
            #expect(!trigger.displayName.isEmpty)
        }
    }

    // MARK: - HookAction displayName

    @Test("HookAction displayName")
    func actionDisplayNames() {
        #expect(HookAction.logToFile(path: "").displayName == "파일에 기록")
        #expect(HookAction.runScript(path: "").displayName == "스크립트 실행")
        #expect(HookAction.systemNotification(title: "").displayName == "시스템 알림")
    }

    // MARK: - Templates

    @Test("내장 템플릿 3개 존재")
    func templates() {
        #expect(UserHook.templates.count == 3)
        // 모두 비활성 상태로 시작
        for template in UserHook.templates {
            #expect(template.isEnabled == false)
        }
    }

    // MARK: - HookContext

    @Test("HookContext 기본값")
    func hookContextDefaults() {
        let ctx = HookContext()
        #expect(ctx.roomID == nil)
        #expect(ctx.roomTitle == nil)
        #expect(ctx.agentName == nil)
        #expect(ctx.command == nil)
        #expect(ctx.filePath == nil)
    }

    @Test("HookContext 전체 필드")
    func hookContextFull() {
        let roomID = UUID()
        let ctx = HookContext(roomID: roomID, roomTitle: "테스트", agentName: "백엔드", command: "ls", filePath: "/tmp/a.txt")
        #expect(ctx.roomID == roomID)
        #expect(ctx.roomTitle == "테스트")
        #expect(ctx.agentName == "백엔드")
        #expect(ctx.command == "ls")
        #expect(ctx.filePath == "/tmp/a.txt")
    }

    // MARK: - HookManager 기본 동작

    @Test("HookManager — CRUD")
    @MainActor
    func hookManagerCRUD() {
        let defaults = makeTestDefaults()
        let manager = HookManager(defaults: defaults)

        // 추가
        let hook = UserHook(name: "테스트", trigger: .roomCompleted, action: .logToFile(path: "~/test.md"))
        manager.addHook(hook)
        #expect(manager.hooks.count == 1)

        // 토글
        manager.toggleHook(id: hook.id)
        #expect(manager.hooks[0].isEnabled == false)

        // 삭제
        manager.removeHook(id: hook.id)
        #expect(manager.hooks.isEmpty)
    }

    @Test("HookManager — matchingHooks 필터링")
    @MainActor
    func hookManagerMatching() {
        let defaults = makeTestDefaults()
        let manager = HookManager(defaults: defaults)

        manager.addHook(UserHook(name: "활성", trigger: .roomCompleted, action: .logToFile(path: "~/a.md"), isEnabled: true))
        manager.addHook(UserHook(name: "비활성", trigger: .roomCompleted, action: .logToFile(path: "~/b.md"), isEnabled: false))
        manager.addHook(UserHook(name: "다른 트리거", trigger: .fileWritten, action: .logToFile(path: "~/c.md"), isEnabled: true))

        let matching = manager.matchingHooks(for: .roomCompleted)
        #expect(matching.count == 1)
        #expect(matching[0].name == "활성")
    }

    @Test("HookManager — 영속성")
    @MainActor
    func hookManagerPersistence() {
        let defaults = makeTestDefaults()

        // 저장
        let manager1 = HookManager(defaults: defaults)
        manager1.addHook(UserHook(name: "영속 테스트", trigger: .roomFailed, action: .systemNotification(title: "실패")))

        // 다시 로드
        let manager2 = HookManager(defaults: defaults)
        #expect(manager2.hooks.count == 1)
        #expect(manager2.hooks[0].name == "영속 테스트")
    }
}
