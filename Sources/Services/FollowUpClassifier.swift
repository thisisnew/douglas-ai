import Foundation

/// 후속 메시지의 의도를 결정론적으로 분류하는 서비스
/// launchFollowUpCycle에서 호출하여 분기/캐리오버/스킵을 결정
struct FollowUpClassifier {

    /// 이전 방 상태
    enum PreviousState {
        case discussionCompleted   // 토론만 완료 (actionItems 유/무)
        case implementCompleted    // 구현 완료
        case failed                // 실패/취소
    }

    /// 후속 메시지 분류
    static func classify(
        message: String,
        previousState: PreviousState,
        hasActionItems: Bool,
        hasBriefing: Bool,
        hasWorkLog: Bool
    ) -> FollowUpDecision {
        let followUpIntent = classifyIntent(
            message: message,
            previousState: previousState,
            hasActionItems: hasActionItems,
            hasBriefing: hasBriefing,
            hasWorkLog: hasWorkLog
        )

        let resolvedIntent = mapToWorkflowIntent(followUpIntent)
        let policy = ContextCarryoverPolicy.policy(for: followUpIntent)
        let skipPhases = determineSkipPhases(followUpIntent)
        let needsPlan = determineNeedsPlan(followUpIntent)

        return FollowUpDecision(
            intent: followUpIntent,
            resolvedWorkflowIntent: resolvedIntent,
            contextPolicy: policy,
            skipPhases: skipPhases,
            needsPlan: needsPlan
        )
    }

    // MARK: - 의도 분류

    private static func classifyIntent(
        message: String,
        previousState: PreviousState,
        hasActionItems: Bool,
        hasBriefing: Bool,
        hasWorkLog: Bool
    ) -> FollowUpIntent {
        let lower = message.lowercased()

        // 1. 재시도 패턴 (실패 상태에서 최우선)
        if previousState == .failed {
            let retryKeywords = ["다시 해", "다시해", "재시도", "retry", "다시 시작", "재실행"]
            if retryKeywords.contains(where: { lower.contains($0) }) {
                return .retryExecution
            }
            let changeKeywords = ["접근을 바꿔", "다른 방법", "다른 접근", "방향을 바꿔"]
            if changeKeywords.contains(where: { lower.contains($0) }) {
                return .restartDiscussion
            }
        }

        // 2. 구현 패턴
        let implementKeywords = ["구현하자", "시작하자", "만들자", "개발하자", "진행하자",
                                  "구현해줘", "시작해줘", "만들어줘", "개발해줘", "진행해줘",
                                  "이제 구현", "이제 개발", "이제 만들"]
        if implementKeywords.contains(where: { lower.contains($0) }) {
            // 부분 구현 체크: "1번이랑 3번만", "첫 번째만"
            if let indices = parseItemIndices(from: lower) {
                return .implementPartial(indices)
            }
            return .implementAll
        }

        // 3. 부분 선택 패턴 (숫자+만)
        if let indices = parseItemIndices(from: lower) {
            let hasImplementHint = ["해줘", "하자", "진행", "실행"].contains(where: { lower.contains($0) })
            if hasImplementHint {
                return .implementPartial(indices)
            }
        }

        // 4. 토론 계속/재시작 패턴
        let continueKeywords = ["더 논의", "더 토론", "추가 논의", "이어서 논의", "계속 토론"]
        if continueKeywords.contains(where: { lower.contains($0) }) {
            return .continueDiscussion
        }

        let restartKeywords = ["다시 논의", "다시 토론", "처음부터", "리셋", "새로"]
        if restartKeywords.contains(where: { lower.contains($0) }) {
            return .restartDiscussion
        }

        // 5. 방향 변경 패턴: "N번 방향을 바꿔"
        let modifyPatterns = ["방향을 바꿔", "방향 바꿔", "다르게", "수정해서", "변경해서"]
        if modifyPatterns.contains(where: { lower.contains($0) }) {
            return .modifyAndDiscuss(message)
        }

        // 6. 검토 패턴
        let reviewKeywords = ["검토해", "리뷰해", "확인해", "잘된 건지", "체크해"]
        if reviewKeywords.contains(where: { lower.contains($0) }) {
            return .reviewResult
        }

        // 7. 문서화 패턴
        let docKeywords = ["정리해", "문서화", "문서로", "보고서", "기획서"]
        if docKeywords.contains(where: { lower.contains($0) }) {
            return .documentResult
        }

        // 8. 기본값: 이전 상태에 따라
        switch previousState {
        case .discussionCompleted where hasActionItems:
            return .implementAll  // actionItems가 있고 명확한 토론 키워드 없으면 구현 의도로 추정
        case .failed:
            return .retryExecution
        default:
            return .newTask
        }
    }

    // MARK: - 매핑

    /// FollowUpIntent → 기존 6개 WorkflowIntent로 매핑
    private static func mapToWorkflowIntent(_ intent: FollowUpIntent) -> WorkflowIntent {
        switch intent {
        case .implementAll, .implementPartial, .retryExecution:
            return .task
        case .continueDiscussion, .modifyAndDiscuss, .restartDiscussion, .reviewResult:
            return .discussion
        case .documentResult:
            return .documentation
        case .newTask:
            return .task
        }
    }

    /// 스킵할 phase 결정
    private static func determineSkipPhases(_ intent: FollowUpIntent) -> Set<WorkflowPhase> {
        switch intent {
        case .implementAll, .implementPartial:
            return [.understand, .assemble]  // 기존 컨텍스트 유지
        case .retryExecution:
            return [.understand, .assemble, .design]  // 같은 계획으로 재실행
        case .continueDiscussion:
            return [.understand, .assemble]
        case .modifyAndDiscuss:
            return [.understand]  // assemble은 유지하되 design부터 재시작
        case .restartDiscussion:
            return [.understand]
        case .reviewResult:
            return [.understand, .assemble]
        case .documentResult:
            return [.understand]
        case .newTask:
            return []  // 전체 플로우
        }
    }

    /// 계획 생성 필요 여부
    private static func determineNeedsPlan(_ intent: FollowUpIntent) -> Bool {
        switch intent {
        case .implementAll, .implementPartial:
            return true
        case .retryExecution:
            return false  // 기존 계획 재사용
        default:
            return false
        }
    }

    // MARK: - 파싱

    /// "1번이랑 3번", "첫 번째, 세 번째", "1, 3" 등에서 인덱스 추출
    static func parseItemIndices(from text: String) -> [Int]? {
        var indices: [Int] = []

        // 숫자 + "번" 패턴
        let numberPattern = try? NSRegularExpression(pattern: "(\\d+)\\s*번", options: [])
        let nsText = text as NSString
        let matches = numberPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            if let range = Range(match.range(at: 1), in: text),
               let num = Int(text[range]) {
                indices.append(num - 1)  // 1-based → 0-based
            }
        }

        // 한글 서수: "첫 번째", "두 번째", "세 번째"
        let ordinalMap = ["첫": 0, "두": 1, "세": 2, "네": 3, "다섯": 4]
        for (word, idx) in ordinalMap {
            if text.contains("\(word) 번째") || text.contains("\(word)번째") {
                if !indices.contains(idx) {
                    indices.append(idx)
                }
            }
        }

        return indices.isEmpty ? nil : indices.sorted()
    }
}
