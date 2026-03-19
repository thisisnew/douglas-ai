import Testing
import Foundation
@testable import DOUGLAS

@Suite("P1 #7: ActionItem completionStatus")
struct ActionItemCompletionTests {

    // MARK: - CompletionStatus 기본

    @Test("ActionItem 기본 completionStatus는 .pending")
    func defaultStatusIsPending() {
        let item = ActionItem(description: "테스트 작업")
        #expect(item.completionStatus == .pending)
    }

    @Test("ActionItem completionStatus를 .completed로 설정")
    func canMarkCompleted() {
        var item = ActionItem(description: "테스트 작업")
        item.completionStatus = .completed
        #expect(item.completionStatus == .completed)
    }

    @Test("ActionItem completionStatus를 .inProgress로 설정")
    func canMarkInProgress() {
        var item = ActionItem(description: "테스트 작업")
        item.completionStatus = .inProgress
        #expect(item.completionStatus == .inProgress)
    }

    // MARK: - 필터링

    @Test("pending 항목만 필터링")
    func filterPendingItems() {
        var items = [
            ActionItem(description: "작업 1"),
            ActionItem(description: "작업 2"),
            ActionItem(description: "작업 3"),
        ]
        items[0].completionStatus = .completed
        items[2].completionStatus = .inProgress

        let pending = items.filter { $0.completionStatus == .pending }
        #expect(pending.count == 1)
        #expect(pending[0].description == "작업 2")
    }

    @Test("완료되지 않은 항목 필터링")
    func filterIncompleteItems() {
        var items = [
            ActionItem(description: "작업 1"),
            ActionItem(description: "작업 2"),
            ActionItem(description: "작업 3"),
        ]
        items[0].completionStatus = .completed

        let incomplete = items.filter { $0.completionStatus != .completed }
        #expect(incomplete.count == 2)
    }

    // MARK: - 컨텍스트 태깅

    @Test("완료 항목에 [완료] 태그 추가")
    func completedItemsTagged() {
        var items = [
            ActionItem(description: "API 설계"),
            ActionItem(description: "DB 스키마"),
            ActionItem(description: "UI 구현"),
        ]
        items[0].completionStatus = .completed

        let tagged = items.map { item -> String in
            let prefix = item.completionStatus == .completed ? "[완료] " : ""
            return "\(prefix)\(item.description)"
        }

        #expect(tagged[0] == "[완료] API 설계")
        #expect(tagged[1] == "DB 스키마")
        #expect(tagged[2] == "UI 구현")
    }

    // MARK: - Codable (하위 호환)

    @Test("completionStatus 없는 JSON 디코딩 → .pending 기본값")
    func decodeLegacyJSONDefaultsToPending() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "description": "레거시 작업",
            "priority": 2
        }
        """
        let data = json.data(using: .utf8)!
        let item = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(item.completionStatus == .pending)
    }

    @Test("completionStatus 있는 JSON 라운드트립")
    func encodeDecodeRoundTrip() throws {
        var item = ActionItem(description: "작업")
        item.completionStatus = .completed

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(decoded.completionStatus == .completed)
    }

    // MARK: - markItemsCompleted 유틸리티

    @Test("인덱스 기반 일괄 완료 처리")
    func markItemsByIndices() {
        var items = [
            ActionItem(description: "작업 1"),
            ActionItem(description: "작업 2"),
            ActionItem(description: "작업 3"),
        ]

        let indices = [0, 2]
        for idx in indices where idx < items.count {
            items[idx].completionStatus = .completed
        }

        #expect(items[0].completionStatus == .completed)
        #expect(items[1].completionStatus == .pending)
        #expect(items[2].completionStatus == .completed)
    }
}
