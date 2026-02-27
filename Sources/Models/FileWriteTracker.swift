import Foundation

/// 병렬 실행 시 파일 쓰기 충돌 감지
actor FileWriteTracker {
    /// 파일 경로 → 마지막으로 쓴 에이전트 ID
    private var writes: [String: UUID] = [:]
    /// 충돌 로그: (filePath, agentIDs)
    private var conflicts: [(path: String, agents: [UUID])] = []

    /// 에이전트가 파일을 썼음을 기록. 충돌 시 true 반환.
    func recordWrite(path: String, agentID: UUID) -> Bool {
        let normalized = (path as NSString).standardizingPath
        if let existing = writes[normalized], existing != agentID {
            if let idx = conflicts.firstIndex(where: { $0.path == normalized }) {
                if !conflicts[idx].agents.contains(agentID) {
                    conflicts[idx].agents.append(agentID)
                }
            } else {
                conflicts.append((path: normalized, agents: [existing, agentID]))
            }
            writes[normalized] = agentID
            return true
        }
        writes[normalized] = agentID
        return false
    }

    /// 현재 충돌 목록
    func getConflicts() -> [(path: String, agents: [UUID])] {
        conflicts
    }

    /// 새 단계 시작 시 초기화
    func reset() {
        writes.removeAll()
        conflicts.removeAll()
    }
}
