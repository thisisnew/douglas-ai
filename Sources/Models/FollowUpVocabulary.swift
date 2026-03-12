import Foundation

/// 후속 의도별 어휘를 캡슐화하는 Value Object
/// FollowUpClassifier에서 키워드 관리 책임을 분리 (SRP)
///
/// 사용법:
///   FollowUpVocabulary.document.matches("요약해줘")  // true
///   FollowUpVocabulary.retry.matches("다시해줘")     // true
struct FollowUpVocabulary: Equatable {
    let intent: FollowUpIntent
    let keywords: [String]

    /// 텍스트에 이 어휘의 키워드가 포함되는지
    func matches(_ text: String) -> Bool {
        keywords.contains(where: { text.contains($0) })
    }
}

// MARK: - 어휘 사전 (Factory)

extension FollowUpVocabulary {

    /// 전체 후속 어휘 사전
    static let all: [FollowUpVocabulary] = [
        .retry, .implement, .continueDiscussion,
        .restart, .modify, .review, .document
    ]

    // MARK: 재시도

    static let retry = FollowUpVocabulary(
        intent: .retryExecution,
        keywords: ["다시 해", "다시해", "재시도", "retry", "다시 시작", "재실행"]
    )

    // MARK: 구현

    static let implement = FollowUpVocabulary(
        intent: .implementAll,
        keywords: [
            "구현하자", "시작하자", "만들자", "개발하자", "진행하자",
            "구현해줘", "시작해줘", "만들어줘", "개발해줘", "진행해줘",
            "이제 구현", "이제 개발", "이제 만들",
        ]
    )

    // MARK: 토론 계속

    static let continueDiscussion = FollowUpVocabulary(
        intent: .continueDiscussion,
        keywords: ["더 논의", "더 토론", "추가 논의", "이어서 논의", "계속 토론"]
    )

    // MARK: 토론 재시작

    static let restart = FollowUpVocabulary(
        intent: .restartDiscussion,
        keywords: ["다시 논의", "다시 토론", "처음부터", "리셋", "새로"]
    )

    // MARK: 방향 변경

    static let modify = FollowUpVocabulary(
        intent: .modifyAndDiscuss(""),
        keywords: ["방향을 바꿔", "방향 바꿔", "다르게", "수정해서", "변경해서"]
    )

    // MARK: 검토

    static let review = FollowUpVocabulary(
        intent: .reviewResult,
        keywords: ["검토해", "리뷰해", "확인해", "잘된 건지", "체크해"]
    )

    // MARK: 문서화

    static let document = FollowUpVocabulary(
        intent: .documentResult,
        keywords: [
            "정리해", "문서화", "문서로", "보고서", "기획서",
            // 신규 (이전 분석 A — "요약해줘" 감지 실패)
            "요약해", "요약으로", "요약본",
        ]
    )
}
