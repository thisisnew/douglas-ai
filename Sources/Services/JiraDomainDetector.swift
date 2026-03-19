import Foundation

/// Jira 티켓 텍스트에서 관련 도메인을 결정론적으로 감지
/// Assemble 단계 LLM 프롬프트에 힌트로 주입하여 에이전트 매칭 정확도 향상
enum JiraDomainDetector {

    /// 감지된 도메인 + 근거 키워드
    struct DomainHint: Equatable {
        let domain: String      // "백엔드", "프론트엔드" 등 한국어 표시명
        let evidence: [String]  // 매칭된 키워드들
    }

    /// 도메인별 키워드 사전
    private static let domainMap: [(domain: String, keywords: [String])] = [
        ("백엔드", ["api", "서버", "엔드포인트", "endpoint", "spring", "django", "express",
                   "db", "database", "쿼리", "query", "rest", "graphql", "grpc",
                   "백엔드", "backend", "마이크로서비스", "microservice"]),
        ("프론트엔드", ["ui", "화면", "페이지", "react", "vue", "angular", "css",
                     "컴포넌트", "component", "레이아웃", "layout", "프론트", "frontend",
                     "프론트엔드", "렌더링", "swiftui", "html", "웹"]),
        ("모바일", ["ios", "android", "앱", "모바일", "mobile", "swift", "kotlin",
                  "flutter", "react native", "푸시", "push"]),
        ("인프라", ["배포", "deploy", "ci/cd", "cicd", "docker", "k8s", "kubernetes",
                  "클라우드", "cloud", "aws", "gcp", "azure", "인프라", "infra",
                  "devops", "terraform", "파이프라인"]),
        ("QA", ["테스트", "test", "qa", "tc", "검증", "품질", "quality",
               "자동화 테스트", "e2e", "regression"]),
        ("디자인", ["디자인", "design", "ux", "ui/ux", "피그마", "figma",
                  "와이어프레임", "wireframe", "시안", "프로토타입"]),
        ("데이터", ["데이터", "data", "ml", "머신러닝", "분석", "analytics",
                  "파이프라인", "etl", "빅데이터", "ai", "모델"]),
        ("기획", ["기획", "요구사항", "prd", "스펙", "spec", "정책", "policy",
                "기획서", "제안서", "프로덕트"]),
    ]

    /// summary + description에서 도메인 키워드 감지
    static func detect(summary: String, description: String) -> [DomainHint] {
        let text = (summary + " " + description).lowercased()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var results: [DomainHint] = []

        for (domain, keywords) in domainMap {
            var matched: [String] = []
            for keyword in keywords {
                if text.contains(keyword) {
                    matched.append(keyword)
                }
            }
            if !matched.isEmpty {
                results.append(DomainHint(domain: domain, evidence: matched))
            }
        }

        return results
    }

    /// 힌트 배열을 사람이 읽기 좋은 문자열로 포맷
    /// 예: "백엔드(API, 서버), 프론트엔드(화면, 렌더링)"
    /// 빈 배열이면 nil
    static func formatHint(_ hints: [DomainHint]) -> String? {
        guard !hints.isEmpty else { return nil }

        let parts = hints.map { hint in
            let evidenceStr = hint.evidence.prefix(3).joined(separator: ", ")
            return "\(hint.domain)(\(evidenceStr))"
        }
        return parts.joined(separator: ", ")
    }
}
