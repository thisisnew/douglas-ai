import Foundation

// MARK: - 한국어 텍스트 유틸리티

/// 한국어 NLP 경량 유틸리티 (형태소 분석 대체)
/// - 스크립트 경계 분리 (한글↔라틴)
/// - 한국어 조사/어미 제거
/// - 의미 키워드 추출
enum KoreanTextUtils {

    /// 한국어 조사 제거 + 스크립트 경계 분리로 의미 키워드 추출
    /// - genericSuffixes 필터링은 호출자 책임 (MatchingVocabulary 의존 방지)
    static func extractSemanticKeywords(from text: String, excluding genericSuffixes: Set<String> = []) -> [String] {
        let tokens = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var keywords: Set<String> = []

        for token in tokens {
            let parts = splitByScript(token)
            for part in parts {
                let subparts = part.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 2 }
                for sub in subparts {
                    let stemmed = stripKoreanSuffix(sub)
                    if stemmed.count >= 2 && !genericSuffixes.contains(stemmed) {
                        keywords.insert(stemmed)
                    }
                    // 원형도 보존 (접미사 제거 전 — 정확 매칭용)
                    if sub.count >= 2 && sub != stemmed && !genericSuffixes.contains(sub) {
                        keywords.insert(sub)
                    }
                }
            }
        }

        return Array(keywords)
    }

    /// 한글↔라틴 스크립트 경계에서 분리 (예: "react와" → ["react", "와"])
    static func splitByScript(_ token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        var prevIsKorean: Bool?

        for char in token {
            let korean = isKoreanCharacter(char)
            if let prev = prevIsKorean, prev != korean, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(char)
            prevIsKorean = korean
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 한국어 조사/어미 제거 (형태소 분석 경량 대체)
    static func stripKoreanSuffix(_ word: String) -> String {
        for suffix in koreanStripSuffixes {
            if word.hasSuffix(suffix) {
                let stem = String(word.dropLast(suffix.count))
                if stem.count >= 2 { return stem }
            }
        }
        return word
    }

    /// 한국어 조사/접미사 리스트 (긴 접미사부터 — greedy 매칭)
    static let koreanStripSuffixes: [String] = [
        "입니다", "습니다", "합니다", "됩니다",
        "으로서", "으로써", "에서의", "한테서", "에게서",
        "에서", "까지", "부터", "으로", "께서", "이랑",
        "하는", "하고", "이며", "에게", "한테", "더러", "보고",
        "을", "를", "이", "가", "은", "는",
        "에", "의", "와", "과", "로", "도", "만", "께", "랑",
    ]

    // MARK: - Private

    private static func isKoreanCharacter(_ char: Character) -> Bool {
        char.unicodeScalars.contains {
            (0xAC00...0xD7A3).contains($0.value) ||  // 완성형 한글
            (0x3131...0x3163).contains($0.value)      // 한글 자모
        }
    }
}
