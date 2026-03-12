import Foundation

// MARK: - 워크플로우 포지션 (매칭 + 토론용 세밀 역할)

/// RuntimeRole(3값)보다 세밀한 12-value 포지션. 에이전트 매칭 및 토론/실행 시 역할 지정에 사용.
enum WorkflowPosition: String, Codable, CaseIterable {
    // 기획/설계
    case architect       // 전체 설계, 아키텍처
    case planner         // 계획/전략 수립

    // 생산
    case implementer     // 코드 구현, 콘텐츠 제작
    case writer          // 문서/보고서 작성
    case translator      // 번역/현지화

    // 검증
    case reviewer        // 코드/문서 리뷰
    case tester          // QA/테스트
    case auditor         // 법무/컴플라이언스/보안 감사

    // 분석
    case researcher      // 조사/리서치
    case analyst         // 데이터/트렌드 분석

    // 조율
    case coordinator     // PM/프로젝트 관리
    case advisor         // 자문/컨설팅

    var displayName: String {
        switch self {
        case .architect:    return "설계/아키텍처"
        case .planner:      return "계획/전략"
        case .implementer:  return "구현/제작"
        case .writer:       return "문서 작성"
        case .translator:   return "번역/현지화"
        case .reviewer:     return "리뷰/검토"
        case .tester:       return "QA/테스트"
        case .auditor:      return "감사/컴플라이언스"
        case .researcher:   return "조사/리서치"
        case .analyst:      return "분석"
        case .coordinator:  return "프로젝트 관리"
        case .advisor:      return "자문/컨설팅"
        }
    }
}
