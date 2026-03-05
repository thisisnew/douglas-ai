import Foundation
import NaturalLanguage

/// 사용자 메시지가 문서화 요청인지 감지 (2단계: NLTokenizer + LLM 폴백)
enum DocumentRequestDetector {

    struct Result {
        let isDocumentRequest: Bool
        let suggestedDocType: DocumentType?
    }

    // MARK: - 1차: NLTokenizer + 키워드 패턴

    /// 빠른 감지. 확실한 경우 Result 반환, 불확실하면 nil (LLM 폴백 필요)
    static func quickDetect(_ text: String) -> Result? {
        let lower = text.lowercased()

        // 강한 문서 출력 패턴 (정규식)
        for trigger in strongTriggers {
            let range = NSRange(lower.startIndex..., in: lower)
            if trigger.regex.firstMatch(in: lower, range: range) != nil {
                return Result(isDocumentRequest: true, suggestedDocType: trigger.docType)
            }
        }

        // NLTokenizer 기반 토큰 조합 감지
        let tokens = tokenize(text)
        if let docType = detectFromTokens(tokens) {
            return Result(isDocumentRequest: true, suggestedDocType: docType)
        }

        return nil
    }

    // MARK: - 2차: LLM 폴백

    /// LLM으로 문서화 요청 여부 판별
    static func detectWithLLM(
        text: String,
        provider: any AIProvider,
        model: String
    ) async -> Result {
        let systemPrompt = """
        사용자 메시지가 문서/파일 출력을 요청하는지 판별하세요.

        문서 요청 예시: "문서로 정리해줘", "보고서로 뽑아줘", "pdf로 만들어줘", "기획서 작성해줘"
        비문서 예시: "더 분석해줘", "다른 관점에서 봐줘", "이해가 안 돼"

        문서 요청이면: YES:docType (prd/technicalDesign/apiDoc/testPlan/report/freeform)
        아니면: NO

        한 단어만 출력하세요.
        """

        do {
            let response = try await provider.sendMessage(
                model: model,
                systemPrompt: systemPrompt,
                messages: [("user", text)]
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return parseResponse(trimmed)
        } catch {
            return Result(isDocumentRequest: false, suggestedDocType: nil)
        }
    }

    // MARK: - 내부 구현

    private struct Trigger {
        let regex: NSRegularExpression
        let docType: DocumentType?
    }

    /// 강한 문서 출력 패턴 (정규식 캐시)
    private static let strongTriggers: [Trigger] = {
        let patterns: [(String, DocumentType?)] = [
            // 구체적 유형 먼저 매칭 (순서 중요)
            ("보고서로\\s?(정리|만들|뽑|작성)", .report),
            ("기획서로\\s?(정리|만들|뽑|작성)", .prd),
            ("prd로\\s?(정리|만들|뽑|작성)", .prd),
            ("테스트\\s?계획서로\\s?(정리|만들|뽑|작성)", .testPlan),
            ("설계\\s?문서로\\s?(정리|만들|뽑|작성)", .technicalDesign),
            ("api\\s?문서로\\s?(정리|만들|뽑|작성)", .apiDoc),
            // 일반 문서/파일 요청 → .freeform (nil이면 hasDocRequest 판정 실패)
            ("문서로\\s?(정리|만들|작성|뽑)", .freeform),
            ("문서\\s?(정리|만들어|작성|뽑아)", .freeform),
            ("파일로\\s?(저장|내보내|뽑|만들)", .freeform),
            ("pdf로?\\s?(정리|만들|뽑|저장|변환)", .freeform),
            ("pdf\\s?만들", .freeform),
            ("마크다운으로?\\s?(정리|만들|뽑|저장)", .freeform),
            ("md로?\\s?(정리|만들|뽑|저장)", .freeform),
            ("md파일로?\\s?(정리|만들|뽑|저장)", .freeform),
            ("워드로?\\s?(정리|만들|뽑|저장)", .freeform),
            ("문서\\s?작성", .freeform),
            ("문서화\\s?해", .freeform),
        ]
        return patterns.compactMap { (pattern, docType) in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return Trigger(regex: regex, docType: docType)
        }
    }()

    /// NLTokenizer로 한국어 텍스트를 토큰으로 분리
    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]).lowercased())
            return true
        }
        return tokens
    }

    /// 토큰 조합으로 문서 요청 감지
    private static func detectFromTokens(_ tokens: [String]) -> DocumentType? {
        let tokenSet = Set(tokens)

        // 출력 동사 존재 여부
        let hasOutputVerb = !tokenSet.isDisjoint(with: ["정리", "작성", "뽑아", "저장", "만들어", "만들어줘", "내보내", "변환"])

        // 문서 유형 키워드
        if hasOutputVerb {
            if !tokenSet.isDisjoint(with: ["기획서", "prd"]) { return .prd }
            if !tokenSet.isDisjoint(with: ["보고서", "리포트"]) { return .report }
            if !tokenSet.isDisjoint(with: ["설계서", "설계"]) && tokenSet.contains("문서") { return .technicalDesign }
            if !tokenSet.isDisjoint(with: ["api"]) && tokenSet.contains("문서") { return .apiDoc }
            if !tokenSet.isDisjoint(with: ["테스트"]) && !tokenSet.isDisjoint(with: ["계획서", "계획"]) { return .testPlan }
            if !tokenSet.isDisjoint(with: ["문서", "파일", "pdf", "마크다운", "md", "워드"]) { return .freeform }
        }

        return nil
    }

    /// LLM 응답 파싱
    private static func parseResponse(_ text: String) -> Result {
        if text.hasPrefix("yes") {
            let parts = text.split(separator: ":")
            let docType: DocumentType?
            if parts.count >= 2 {
                docType = parseDocType(String(parts[1]).trimmingCharacters(in: .whitespaces))
            } else {
                docType = .freeform
            }
            return Result(isDocumentRequest: true, suggestedDocType: docType)
        }
        return Result(isDocumentRequest: false, suggestedDocType: nil)
    }

    private static func parseDocType(_ text: String) -> DocumentType? {
        switch text {
        case "prd":              return .prd
        case "technicaldesign":  return .technicalDesign
        case "apidoc":           return .apiDoc
        case "testplan":         return .testPlan
        case "report":           return .report
        case "freeform":         return .freeform
        default:                 return .freeform
        }
    }
}
