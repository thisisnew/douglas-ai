import Testing
import Foundation
@testable import DOUGLAS

@Suite("FileWriteTracker Tests")
struct FileWriteTrackerTests {

    @Test("첫 쓰기는 충돌 없음")
    func firstWriteNoConflict() async {
        let tracker = FileWriteTracker()
        let conflict = await tracker.recordWrite(path: "/tmp/a.swift", agentID: UUID())
        #expect(conflict == false)
    }

    @Test("같은 에이전트 재쓰기는 충돌 아님")
    func sameAgentNoConflict() async {
        let tracker = FileWriteTracker()
        let agentID = UUID()
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agentID)
        let conflict = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agentID)
        #expect(conflict == false)
    }

    @Test("다른 에이전트 쓰기는 충돌 감지")
    func differentAgentConflict() async {
        let tracker = FileWriteTracker()
        let agent1 = UUID()
        let agent2 = UUID()
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent1)
        let conflict = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent2)
        #expect(conflict == true)
    }

    @Test("충돌 목록 조회")
    func getConflicts() async {
        let tracker = FileWriteTracker()
        let agent1 = UUID()
        let agent2 = UUID()
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent1)
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent2)
        let conflicts = await tracker.getConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts[0].agents.count == 2)
    }

    @Test("reset 후 충돌 초기화")
    func resetClearsAll() async {
        let tracker = FileWriteTracker()
        let agent1 = UUID()
        let agent2 = UUID()
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent1)
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent2)
        await tracker.reset()
        let conflicts = await tracker.getConflicts()
        #expect(conflicts.isEmpty)
        // reset 후 새 쓰기는 충돌 없음
        let conflict = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent1)
        #expect(conflict == false)
    }

    @Test("다른 파일은 독립적")
    func differentFilesIndependent() async {
        let tracker = FileWriteTracker()
        let agent1 = UUID()
        let agent2 = UUID()
        _ = await tracker.recordWrite(path: "/tmp/a.swift", agentID: agent1)
        let conflict = await tracker.recordWrite(path: "/tmp/b.swift", agentID: agent2)
        #expect(conflict == false)
        let conflicts = await tracker.getConflicts()
        #expect(conflicts.isEmpty)
    }

    @Test("3명 이상 에이전트 충돌 추적")
    func threeAgentConflict() async {
        let tracker = FileWriteTracker()
        let agent1 = UUID()
        let agent2 = UUID()
        let agent3 = UUID()
        _ = await tracker.recordWrite(path: "/tmp/shared.swift", agentID: agent1)
        _ = await tracker.recordWrite(path: "/tmp/shared.swift", agentID: agent2)
        _ = await tracker.recordWrite(path: "/tmp/shared.swift", agentID: agent3)
        let conflicts = await tracker.getConflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts[0].agents.count == 3)
    }
}
