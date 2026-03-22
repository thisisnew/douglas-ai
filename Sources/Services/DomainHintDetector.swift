import Foundation

/// 텍스트에서 관련 도메인을 결정론적으로 감지하는 도메인 서비스
/// Assemble 단계 LLM 프롬프트 및 AgentMatcher에 힌트로 주입하여 에이전트 매칭 정확도 향상
enum DomainHintDetector {

    /// 감지된 도메인 + 근거 키워드 (Value Object)
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

    /// 단일 텍스트에서 도메인 감지 (사용자 입력, 요약 등 범용)
    static func detect(text: String) -> [DomainHint] {
        detect(summary: text, description: "")
    }

    /// 여러 소스의 힌트를 병합 (도메인 기준 중복 제거, evidence 합산)
    static func merge(_ sources: [DomainHint]...) -> [DomainHint] {
        var grouped: [String: Set<String>] = [:]
        for hints in sources {
            for hint in hints {
                grouped[hint.domain, default: []].formUnion(hint.evidence)
            }
        }
        return grouped.map { DomainHint(domain: $0.key, evidence: Array($0.value).sorted()) }
            .sorted { $0.evidence.count > $1.evidence.count }
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
