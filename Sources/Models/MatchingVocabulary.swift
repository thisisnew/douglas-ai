import Foundation

// MARK: - 매칭 어휘 사전 (Value Object)

/// 에이전트 매칭에 사용되는 어휘 사전 + 어휘 관련 유틸리티
/// - 동의어 그룹 (한국어/영문 기술 스택)
/// - 범용 접미사 (false positive 방지)
/// - 도메인 키워드 (문서 intent 필터링)
/// - 짧은 키워드 단어 경계 매칭
struct MatchingVocabulary {
    let synonymGroups: [[String]]
    let genericSuffixes: Set<String>
    let domainKeywords: Set<String>

    /// 키워드를 동의어로 확장 (원본 포함)
    func expandSynonyms(_ keywords: [String]) -> [String] {
        var expanded = Set(keywords)
        for kw in keywords {
            let lower = kw.lowercased()
            for group in synonymGroups {
                if group.contains(where: { $0 == lower }) {
                    expanded.formUnion(group)
                }
            }
        }
        return Array(expanded)
    }

    /// 범용 접미사 여부 확인
    func isGenericSuffix(_ keyword: String) -> Bool {
        genericSuffixes.contains(keyword)
    }

    /// 짧은 키워드(≤3자)의 부분 문자열 false positive 방지
    func containsWholeWord(_ text: String, keyword: String) -> Bool {
        if keyword.count <= 3 {
            if text == keyword { return true }
            let pattern = "(?:^|[^a-zA-Z가-힣])\(NSRegularExpression.escapedPattern(for: keyword))(?:$|[^a-zA-Z가-힣])"
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return text.contains(keyword) || keyword.contains(text)
    }

    // MARK: - 기본 사전

    static let `default` = MatchingVocabulary(
        synonymGroups: [
            // 기존 10그룹
            ["fe", "프론트엔드", "프론트", "frontend", "front-end"],
            ["be", "백엔드", "백앤드", "backend", "back-end", "서버"],
            ["devops", "인프라", "sre", "클라우드", "cloud", "배포"],
            ["qa", "테스트", "test", "품질", "quality"],
            ["pm", "기획", "기획자", "product", "프로덕트"],
            ["ux", "ui", "디자인", "design", "디자이너"],
            ["ml", "머신러닝", "딥러닝", "데이터사이언스"],
            ["security", "보안", "인증", "auth"],
            ["dba", "데이터베이스", "db", "database"],
            ["문서", "docs", "documentation", "테크니컬라이팅"],
            // 플랫폼/언어별
            ["ios", "아이오에스", "swift", "swiftui", "uikit", "애플"],
            ["android", "안드로이드", "kotlin", "코틀린"],
            ["react", "리액트", "nextjs", "next.js"],
            ["vue", "뷰", "vuejs", "nuxt"],
            ["node", "nodejs", "노드", "express", "nestjs"],
            ["python", "파이썬", "django", "flask", "fastapi"],
            ["go", "golang", "고랭"],
            ["rust", "러스트"],
            ["java", "자바", "spring", "스프링", "springboot"],
            // 비개발 직군
            ["마케팅", "marketing", "growth", "그로스", "seo"],
            ["법무", "법률", "legal", "컴플라이언스", "compliance"],
            ["cs", "고객지원", "customer support", "고객"],
            ["데이터분석", "analytics", "bi", "태블로", "tableau"],
            ["콘텐츠", "content", "카피라이팅", "copywriting", "에디터"],
            ["번역", "translation", "로컬라이제이션", "localization", "i18n"],
            // 기술 영역
            ["아키텍처", "architecture", "설계", "시스템설계"],
            ["네트워크", "network", "tcp", "http"],
            ["성능", "performance", "최적화", "optimization", "튜닝"],
            ["테크니컬라이터", "technical writer", "기술문서", "api문서"],
        ],
        genericSuffixes: [
            "전문가", "개발자", "엔지니어", "담당자", "관리자", "분석가", "설계자", "디자이너",
            "리더", "시니어", "주니어", "팀장", "책임자", "연구원", "컨설턴트",
            "expert", "developer", "engineer", "manager", "analyst", "designer",
            "lead", "senior", "junior", "consultant", "architect", "specialist",
        ],
        domainKeywords: [
            "백엔드", "프론트엔드", "프론트", "인프라", "데이터", "모바일",
            "ios", "android", "웹", "backend", "frontend", "mobile", "devops",
            "서버", "클라이언트", "db", "database", "cloud", "클라우드",
        ]
    )
}
