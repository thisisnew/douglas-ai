import Foundation

/// 토론 히스토리 필터링 — .discussionRound 등 비발언 메시지 제외 + suffix(20) 적용
enum DiscussionHistoryFilter {

    /// 토론 히스토리에 포함할 메시지만 필터링 (suffix(20) 적용)
    /// - .discussionRound (라운드 마커) 제외 — suffix 슬롯 낭비 방지
    /// - .text (사용자 입력), .discussion (에이전트 발언)만 포함
    static func filterForHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages
            .filter { $0.messageType == .text || $0.messageType == .discussion }
            .suffix(20)
            .map { $0 }  // ArraySlice → Array
    }
}
