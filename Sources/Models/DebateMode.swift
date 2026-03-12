import Foundation

/// 토론 유형 — 에이전트 역할 겹침도 + 주제에 따라 결정
/// - dialectic: 같은 도메인, 다른 해법 → 대립/논쟁 (아키텍처 선택, 기술 스택 등)
/// - collaborative: 다른 도메인, 통합 필요 → 종합/연결 (백엔드+프론트 기능개발 등)
/// - coordination: 방향 확정, 세부 조율 → 정렬/확인 (API 스펙 확정, 일정 등)
enum DebateMode: String, Codable, CaseIterable {
    case dialectic      // 대립: 겹치는 영역에서 트레이드오프 탐색
    case collaborative  // 종합: 보완적 영역에서 연결점·갭 발견
    case coordination   // 조율: 구현 세부사항 정렬

    /// 모드별 최대 토론 라운드 수 (WORKFLOW_SPEC §10.1)
    var maxRounds: Int {
        switch self {
        case .dialectic:    return 3  // 대립은 빠르게 수렴해야
        case .collaborative: return 2  // 종합은 1-2회면 충분
        case .coordination:  return 2  // 조율은 간결해야
        }
    }
}
