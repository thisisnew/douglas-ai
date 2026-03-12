import Foundation

/// 사용자 요청의 모호성을 감지하는 도메인 서비스
/// IntentClassifier.hasExplicitUserIntent()에서 분리 (SRP)
///
/// 모호 판정 기준:
/// - 대명사 + 범용 동사 조합 (대상 불명)
/// - URL만 있고 구체적 텍스트 없음
/// - 첨부파일이 있으면 대명사 허용
struct AmbiguityDetector {

    /// 모호성 판정 결과
    struct Result: Equatable {
        let isAmbiguous: Bool
        let reason: AmbiguityReason?
    }

    enum AmbiguityReason: Equatable {
        case pronounOnly          // "이거 바꿔줘" — 대명사만, 대상 불명
        case noActionableContext   // URL만, 텍스트 거의 없음
    }

    /// 대명사 사전
    private static let vaguePronouns = ["이거", "그거", "저거", "이것", "그것", "저것"]

    /// 범용 동사 — 대상 없이 쓰이면 모호
    private static let genericActions = ["바꿔", "고쳐", "좋게", "손봐", "개선", "변경"]

    /// 모호성 판정
    static func detect(text: String, hasAttachments: Bool) -> Result {
        // 첨부파일 있으면 대명사 허용 ("이거 분석해줘" + 파일)
        if hasAttachments {
            return Result(isAmbiguous: false, reason: nil)
        }

        let cleaned = removeURLsAndJiraData(text)
        guard cleaned.count > 2 else {
            return Result(isAmbiguous: true, reason: .noActionableContext)
        }

        // 대명사 + 범용 동사 조합 감지
        let hasPronoun = vaguePronouns.contains(where: { cleaned.contains($0) })
        if hasPronoun {
            let withoutPronouns = vaguePronouns.reduce(cleaned) {
                $0.replacingOccurrences(of: $1, with: "")
            }.trimmingCharacters(in: .whitespacesAndNewlines)

            let onlyGenericAction = genericActions.contains(where: { withoutPronouns.contains($0) })
                && withoutPronouns.count < 15

            if onlyGenericAction {
                return Result(isAmbiguous: true, reason: .pronounOnly)
            }
        }

        return Result(isAmbiguous: false, reason: nil)
    }

    /// URL + Jira 첨부 데이터 제거 후 사용자 텍스트만 추출
    private static func removeURLsAndJiraData(_ text: String) -> String {
        // Jira 첨부 데이터 제거 (--- Jira 티켓 내용 ... --- 끝 ---)
        var userText = text
        if let jiraStart = text.range(of: "--- jira", options: .caseInsensitive) {
            userText = String(text[text.startIndex..<jiraStart.lowerBound])
        }

        // URL 제거
        let withoutURLs = userText.replacingOccurrences(
            of: "https?://[^\\s]+",
            with: "",
            options: .regularExpression
        )

        return withoutURLs.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
