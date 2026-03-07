import Foundation

/// 워크플로우 실행기(WorkflowCoordinator)가 RoomManager에 접근하기 위한 프로토콜.
/// RoomManager가 구현하며, 테스트 시 mock 가능.
@MainActor
protocol WorkflowHost: AnyObject {

    // MARK: - Room 접근

    /// 특정 방 조회 (읽기 전용 스냅샷)
    func room(for id: UUID) -> Room?

    /// 특정 방의 상태를 변경
    func updateRoom(id: UUID, _ mutate: (inout Room) -> Void)

    // MARK: - 메시지

    /// 방에 메시지 추가
    func appendMessage(_ message: ChatMessage, to roomID: UUID)

    /// 기존 메시지 내용 업데이트 (스트리밍)
    func updateMessageContent(_ messageID: UUID, newContent: String, in roomID: UUID)

    /// 특정 메시지 앞에 삽입
    func insertMessage(_ message: ChatMessage, to roomID: UUID, beforeMessageID: UUID)

    // MARK: - 상태 관리

    /// 에이전트 상태 동기화
    func syncAgentStatuses()

    /// 변경사항 저장 예약
    func scheduleSave()

    /// 현재 발화 중인 에이전트 설정/해제
    var speakingAgentIDByRoom: [UUID: UUID] { get set }

    // MARK: - 승인 게이트

    /// 승인 대기 continuation 딕셔너리
    var approvalContinuations: [UUID: CheckedContinuation<Bool, Never>] { get set }

    /// 사용자 입력 대기 continuation
    var userInputContinuations: [UUID: CheckedContinuation<String, Never>] { get set }

    /// Intent 선택 대기 continuation
    var intentContinuations: [UUID: CheckedContinuation<WorkflowIntent, Never>] { get set }

    /// 문서 유형 선택 대기 continuation
    var docTypeContinuations: [UUID: CheckedContinuation<DocumentType, Never>] { get set }

    /// 팀 구성 확인 대기 continuation
    var teamConfirmationContinuations: [UUID: CheckedContinuation<Set<UUID>?, Never>] { get set }

    /// ask_user 선택지
    var pendingQuestionOptions: [UUID: [String]] { get set }

    /// Intent 선택 UI 상태
    var pendingIntentSelection: [UUID: WorkflowIntent] { get set }

    /// 문서 유형 선택 UI 상태
    var pendingDocTypeSelection: [UUID: Bool] { get set }

    /// 팀 구성 확인 UI 상태
    var pendingTeamConfirmation: [UUID: TeamConfirmationState] { get set }

    /// 리뷰 자동 승인 카운트다운
    var reviewAutoApprovalRemaining: [UUID: Int] { get set }

    // MARK: - 외부 의존성

    /// 에이전트 저장소
    var agentStore: AgentStore? { get }

    /// 프로바이더 매니저
    var providerManager: ProviderManager? { get }

    /// 플러그인 이벤트 디스패치
    var pluginEventDelegate: ((PluginEvent) -> Void)? { get }

    /// 플러그인 도구 인터셉트
    var pluginInterceptToolDelegate: ((String, [String: String]) async -> ToolInterceptResult)? { get }

    // MARK: - 멘션/사이클 추적

    /// 멘션으로 지명된 에이전트
    var mentionedAgentIDsByRoom: [UUID: [UUID]] { get set }

    /// 이전 사이클 에이전트 수
    var previousCycleAgentCount: [UUID: Int] { get set }

    // MARK: - 유틸리티

    /// 마스터 에이전트 이름
    var masterAgentName: String { get }

    /// 자동 승인 타이머 시작
    func startReviewAutoApproval(roomID: UUID, seconds: Int)

    /// 자동 승인 타이머 취소
    func cancelReviewAutoApproval(roomID: UUID)

    /// 에이전트 추가
    func addAgent(_ agentID: UUID, to roomID: UUID, silent: Bool)

    /// 에이전트 생성 제안 추가
    func addAgentSuggestion(_ suggestion: RoomAgentSuggestion, to roomID: UUID)
}
