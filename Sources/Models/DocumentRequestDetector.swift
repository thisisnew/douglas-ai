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

    // MARK: - 포맷 변환 판별

    /// 문서 요청 메시지가 기존 대화 내용의 포맷 변환인지 판별
    /// true = 순수 포맷 변환 (새 작업 없음), false = 새 작업 포함
    static func isFormatConversionOnly(_ text: String) -> Bool {
        // 포맷/문서 관련 어간 — 이 어간으로 시작하는 토큰은 "포맷 요청"으로 간주
        let formatStems: Set<String> = [
            // 문서/파일 유형
            "md", "파일", "문서", "보고서", "마크다운", "markdown", "pdf", "워드", "word",
            // 동작 어간
            "만들", "정리", "작성", "뽑", "저장", "내보내", "변환",
            // 지시/참조 (기존 내용을 가리키는 표현)
            "이거", "이걸", "위의", "결과", "내용", "대화",
            // 연결/조사 (2자 이상)
            "해줘", "해서", "으로", "까지", "에서",
        ]

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var totalMeaningful = 0
        var formatMatched = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            guard token.count >= 2 else { return true }  // 1자 토큰 스킵 (조사, 어미)
            totalMeaningful += 1
            if formatStems.contains(where: { token.hasPrefix($0) }) {
                formatMatched += 1
            }
            return true
        }
        return totalMeaningful == 0 || formatMatched == totalMeaningful
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

        문서 요청 = 결과물을 문서 형태로 만들어달라는 요청
        문서 요청 예시: "문서로 정리해줘", "보고서로 뽑아줘", "pdf로 만들어줘", "기획서 작성해줘"

        비문서 = 단순 질문, 정보 요청, 설명 요청, 분석 요청
        비문서 예시: "~에 대해 알려줘", "~가 뭐야", "~설명해줘", "더 분석해줘", "다른 관점에서 봐줘", "이해가 안 돼", "~이 뭔지 궁금해", "~해줘"

        중요: "알려줘", "설명해줘", "뭐야", "궁금해" 등 정보를 묻는 표현은 문서 요청이 아닙니다.

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
            ("보고서로?\\s?(정리|만들|뽑|작성|생성)", .report),
            ("기획서로?\\s?(정리|만들|뽑|작성|생성)", .prd),
            ("prd로?\\s?(정리|만들|뽑|작성|생성)", .prd),
            ("테스트\\s?계획서로?\\s?(정리|만들|뽑|작성|생성)", .testPlan),
            ("설계\\s?문서로?\\s?(정리|만들|뽑|작성|생성)", .technicalDesign),
            ("api\\s?문서로?\\s?(정리|만들|뽑|작성|생성)", .apiDoc),
            // 일반 문서/파일 요청 → .freeform (nil이면 hasDocRequest 판정 실패)
            ("문서로\\s?(정리|만들|작성|뽑|생성)", .freeform),
            ("문서\\s?(정리|만들어|작성|뽑아|생성)", .freeform),
            ("파일로\\s?(저장|내보내|뽑|만들|생성)", .freeform),
            ("pdf로?\\s?(정리|만들|뽑|저장|변환|생성)", .freeform),
            ("pdf\\s?(만들|생성)", .freeform),
            ("마크다운으로?\\s?(정리|만들|뽑|저장|생성)", .freeform),
            ("md로?\\s?(정리|만들|뽑|저장|생성)", .freeform),
            ("md\\s?파일로?\\s?(정리|만들|뽑|저장|생성)", .freeform),
            ("워드로?\\s?(정리|만들|뽑|저장|생성)", .freeform),
            ("문서\\s?(작성|생성)", .freeform),
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
        // 출력 동사 어간 (prefix 매칭 — 한국어 활용 대응: 만들어줘, 생성해줘, 작성할 등)
        let actionStems: Set<String> = ["만들", "생성", "작성", "정리", "뽑", "저장", "내보내", "변환"]
        let hasOutputVerb = tokens.contains { token in
            actionStems.contains(where: { token.hasPrefix($0) })
        }

        let tokenSet = Set(tokens)

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
