import Testing
import Foundation
@testable import DOUGLAS

@Suite("ProjectPlaybook Tests")
struct ProjectPlaybookTests {

    // MARK: - ProjectPlaybook 초기화

    @Test("ProjectPlaybook 기본 초기화 — 모든 옵셔널 nil, 배열 빈 상태")
    func playbookDefaultInit() {
        let pb = ProjectPlaybook()
        #expect(pb.userRole == nil)
        #expect(pb.defaultIntent == nil)
        #expect(pb.branchPattern == nil)
        #expect(pb.baseBranch == nil)
        #expect(pb.afterComplete == nil)
        #expect(pb.testStrategy == nil)
        #expect(pb.codeReviewPolicy == nil)
        #expect(pb.deployProcess == nil)
        #expect(pb.notes.isEmpty)
        #expect(pb.overrides.isEmpty)
    }

    @Test("ProjectPlaybook 전체 파라미터 초기화")
    func playbookFullInit() {
        let pb = ProjectPlaybook(
            userRole: .developer,
            defaultIntent: WorkflowIntent.task,
            branchPattern: "feature/{desc}",
            baseBranch: "main",
            afterComplete: .commitOnly,
            testStrategy: "단위 테스트 필수",
            codeReviewPolicy: "PR 필수",
            deployProcess: "자동 배포",
            notes: ["참고1"],
            overrides: []
        )
        #expect(pb.userRole == .developer)
        #expect(pb.defaultIntent == WorkflowIntent.task)
        #expect(pb.branchPattern == "feature/{desc}")
        #expect(pb.baseBranch == "main")
        #expect(pb.afterComplete == .commitOnly)
        #expect(pb.testStrategy == "단위 테스트 필수")
        #expect(pb.codeReviewPolicy == "PR 필수")
        #expect(pb.deployProcess == "자동 배포")
        #expect(pb.notes == ["참고1"])
    }

    @Test("ProjectPlaybook Codable 라운드트립")
    func playbookCodable() throws {
        let pb = ProjectPlaybook(
            userRole: .qa,
            defaultIntent: WorkflowIntent.task,
            branchPattern: "test/{desc}",
            baseBranch: "develop",
            afterComplete: .createPR,
            testStrategy: "통합 테스트",
            notes: ["메모1", "메모2"]
        )
        let data = try JSONEncoder().encode(pb)
        let decoded = try JSONDecoder().decode(ProjectPlaybook.self, from: data)
        #expect(decoded.userRole == .qa)
        #expect(decoded.defaultIntent == WorkflowIntent.task)
        #expect(decoded.branchPattern == "test/{desc}")
        #expect(decoded.baseBranch == "develop")
        #expect(decoded.afterComplete == .createPR)
        #expect(decoded.testStrategy == "통합 테스트")
        #expect(decoded.notes.count == 2)
    }

    // MARK: - 프리셋

    @Test("startup 프리셋")
    func startupPreset() {
        let pb = ProjectPlaybook.startup
        #expect(pb.baseBranch == "main")
        #expect(pb.afterComplete == .commitOnly)
        #expect(pb.branchPattern == "feature/{desc}")
    }

    @Test("team 프리셋")
    func teamPreset() {
        let pb = ProjectPlaybook.team
        #expect(pb.baseBranch == "develop")
        #expect(pb.afterComplete == .createPR)
        #expect(pb.codeReviewPolicy != nil)
    }

    @Test("enterprise 프리셋")
    func enterprisePreset() {
        let pb = ProjectPlaybook.enterprise
        #expect(pb.baseBranch == "develop")
        #expect(pb.afterComplete == .createPR)
        #expect(pb.deployProcess != nil)
    }

    // MARK: - asContextString

    @Test("asContextString — 비어있는 플레이북")
    func contextStringEmpty() {
        let pb = ProjectPlaybook()
        let str = pb.asContextString()
        #expect(str.contains("[프로젝트 플레이북]"))
        // 옵셔널 필드가 없으므로 최소 내용만
        #expect(!str.contains("브랜치"))
    }

    @Test("asContextString — 모든 필드 포함")
    func contextStringFull() {
        let pb = ProjectPlaybook(
            branchPattern: "feature/{desc}",
            baseBranch: "main",
            afterComplete: .createPR,
            testStrategy: "단위 테스트",
            codeReviewPolicy: "PR 리뷰",
            deployProcess: "CI/CD",
            notes: ["참고 사항"]
        )
        let str = pb.asContextString()
        #expect(str.contains("브랜치: feature/{desc}"))
        #expect(str.contains("베이스 브랜치: main"))
        #expect(str.contains("완료 후: PR 생성"))
        #expect(str.contains("테스트: 단위 테스트"))
        #expect(str.contains("코드 리뷰: PR 리뷰"))
        #expect(str.contains("배포: CI/CD"))
        #expect(str.contains("참고: 참고 사항"))
    }

    // MARK: - UserRole

    @Test("UserRole 전체 케이스")
    func userRoleAllCases() {
        #expect(UserRole.allCases.count == 4)
    }

    @Test("UserRole displayName 비어있지 않음")
    func userRoleDisplayNames() {
        for role in UserRole.allCases {
            #expect(!role.displayName.isEmpty)
        }
    }

    @Test("UserRole defaultIntent 매핑")
    func userRoleDefaultIntents() {
        #expect(UserRole.developer.defaultIntent == WorkflowIntent.task)
        #expect(UserRole.planner.defaultIntent == WorkflowIntent.task)
        #expect(UserRole.qa.defaultIntent == WorkflowIntent.task)
        #expect(UserRole.pm.defaultIntent == WorkflowIntent.task)
    }

    @Test("UserRole Codable 라운드트립")
    func userRoleCodable() throws {
        for role in UserRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(UserRole.self, from: data)
            #expect(decoded == role)
        }
    }

    // MARK: - AfterComplete

    @Test("AfterComplete 전체 케이스")
    func afterCompleteAllCases() {
        #expect(AfterComplete.allCases.count == 3)
    }

    @Test("AfterComplete displayName 비어있지 않음")
    func afterCompleteDisplayNames() {
        for ac in AfterComplete.allCases {
            #expect(!ac.displayName.isEmpty)
        }
    }

    @Test("AfterComplete Codable 라운드트립")
    func afterCompleteCodable() throws {
        for ac in AfterComplete.allCases {
            let data = try JSONEncoder().encode(ac)
            let decoded = try JSONDecoder().decode(AfterComplete.self, from: data)
            #expect(decoded == ac)
        }
    }

    // MARK: - PlaybookOverride

    @Test("PlaybookOverride 기본 초기화")
    func overrideInit() {
        let o = PlaybookOverride(
            field: "baseBranch",
            originalValue: "develop",
            overrideValue: "main",
            reason: "긴급 핫픽스"
        )
        #expect(o.field == "baseBranch")
        #expect(o.originalValue == "develop")
        #expect(o.overrideValue == "main")
        #expect(o.reason == "긴급 핫픽스")
    }

    @Test("PlaybookOverride Codable 라운드트립")
    func overrideCodable() throws {
        let o = PlaybookOverride(
            field: "testStrategy",
            overrideValue: "스킵",
            reason: "프로토타입"
        )
        let data = try JSONEncoder().encode(o)
        let decoded = try JSONDecoder().decode(PlaybookOverride.self, from: data)
        #expect(decoded.id == o.id)
        #expect(decoded.field == "testStrategy")
        #expect(decoded.originalValue == nil)
        #expect(decoded.overrideValue == "스킵")
    }

    // MARK: - PlaybookManager

    @Test("PlaybookManager.recordOverride — 오버라이드 추가")
    func recordOverride() {
        var pb = ProjectPlaybook()
        #expect(pb.overrides.isEmpty)

        PlaybookManager.recordOverride(
            in: &pb,
            field: "baseBranch",
            originalValue: "develop",
            overrideValue: "main",
            reason: "테스트"
        )
        #expect(pb.overrides.count == 1)
        #expect(pb.overrides[0].field == "baseBranch")
    }

    @Test("PlaybookManager.pendingSuggestions — threshold 미달")
    func pendingSuggestionsBelow() {
        var pb = ProjectPlaybook()
        // 2회 기록 — threshold(3) 미달
        PlaybookManager.recordOverride(in: &pb, field: "baseBranch", originalValue: nil, overrideValue: "main", reason: "1")
        PlaybookManager.recordOverride(in: &pb, field: "baseBranch", originalValue: nil, overrideValue: "main", reason: "2")
        let suggestions = PlaybookManager.pendingSuggestions(in: pb)
        #expect(suggestions.isEmpty)
    }

    @Test("PlaybookManager.pendingSuggestions — threshold 충족")
    func pendingSuggestionsAbove() {
        var pb = ProjectPlaybook()
        // 3회 기록 — threshold(3) 충족
        PlaybookManager.recordOverride(in: &pb, field: "baseBranch", originalValue: nil, overrideValue: "main", reason: "1")
        PlaybookManager.recordOverride(in: &pb, field: "baseBranch", originalValue: nil, overrideValue: "main", reason: "2")
        PlaybookManager.recordOverride(in: &pb, field: "baseBranch", originalValue: nil, overrideValue: "main", reason: "3")
        let suggestions = PlaybookManager.pendingSuggestions(in: pb)
        #expect(suggestions.count == 1)
        #expect(suggestions[0].field == "baseBranch")
    }

    @Test("PlaybookManager save/load 라운드트립")
    func saveAndLoad() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let pb = ProjectPlaybook(
            branchPattern: "feature/{desc}",
            baseBranch: "main",
            afterComplete: .commitOnly,
            notes: ["테스트"]
        )
        try PlaybookManager.save(pb, to: tmpDir)
        let loaded = PlaybookManager.load(from: tmpDir)
        #expect(loaded != nil)
        #expect(loaded?.branchPattern == "feature/{desc}")
        #expect(loaded?.baseBranch == "main")
        #expect(loaded?.afterComplete == .commitOnly)
        #expect(loaded?.notes == ["테스트"])
    }

    @Test("PlaybookManager load — 파일 없으면 nil")
    func loadNonexistent() {
        let result = PlaybookManager.load(from: "/nonexistent/path")
        #expect(result == nil)
    }
}
