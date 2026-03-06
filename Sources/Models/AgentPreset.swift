import Foundation

/// 에이전트 등록 프리셋
struct AgentPreset: Identifiable {
    let id: String              // slug
    let name: String            // "백엔드 엔지니어"
    let icon: String            // SF Symbol
    let category: PresetCategory
    let tags: [String]
    let modes: Set<WorkMode>
    let outputs: Set<OutputStyle>
    let suggestedPersona: String

    /// 프리셋에서 Agent를 생성할 때 사용할 기본 페르소나
    var defaultPersona: String { suggestedPersona }

    /// "직접 설정" 프리셋인지 여부
    var isCustom: Bool { id == "custom" }

    enum PresetCategory: String, CaseIterable {
        case custom = "직접 설정"
        case development = "개발"
        case planning = "기획/분석"
        case content = "콘텐츠"
        case operations = "운영/법무"
    }
}

// MARK: - 빌트인 프리셋

extension AgentPreset {
    static let builtIn: [AgentPreset] = [
        // 직접 설정
        AgentPreset(
            id: "custom",
            name: "직접 설정",
            icon: "person.badge.plus",
            category: .custom,
            tags: [],
            modes: [],
            outputs: [],
            suggestedPersona: ""
        ),

        // 개발
        AgentPreset(
            id: "backend-engineer",
            name: "백엔드 엔지니어",
            icon: "server.rack",
            category: .development,
            tags: ["spring", "java", "db", "api", "server", "backend", "백엔드"],
            modes: [.create, .execute, .review],
            outputs: [.code, .document],
            suggestedPersona: "백엔드 시스템 설계 및 API 개발 전문가. REST API, 데이터베이스, 서버 아키텍처를 담당합니다."
        ),
        AgentPreset(
            id: "frontend-engineer",
            name: "프론트엔드 엔지니어",
            icon: "macwindow",
            category: .development,
            tags: ["react", "vue", "css", "ui", "typescript", "frontend", "프론트엔드"],
            modes: [.create, .execute, .review],
            outputs: [.code],
            suggestedPersona: "프론트엔드 UI/UX 구현 전문가. React/Vue 컴포넌트, 스타일링, 사용자 인터랙션을 담당합니다."
        ),
        AgentPreset(
            id: "qa-engineer",
            name: "QA 엔지니어",
            icon: "checkmark.shield",
            category: .development,
            tags: ["test", "automation", "quality", "bug", "qa", "테스트"],
            modes: [.review, .execute],
            outputs: [.code, .review],
            suggestedPersona: "품질 보증 및 테스트 자동화 전문가. 테스트 케이스 설계, 버그 탐지, 코드 리뷰를 담당합니다."
        ),
        AgentPreset(
            id: "devops",
            name: "DevOps",
            icon: "cloud",
            category: .development,
            tags: ["docker", "k8s", "ci/cd", "aws", "deploy", "infra", "인프라"],
            modes: [.execute, .plan],
            outputs: [.code],
            suggestedPersona: "인프라 및 배포 파이프라인 전문가. CI/CD, 컨테이너, 클라우드 인프라를 담당합니다."
        ),

        // 비개발
        AgentPreset(
            id: "pm-planner",
            name: "기획자/PM",
            icon: "chart.bar.doc.horizontal",
            category: .planning,
            tags: ["전략", "로드맵", "요구사항", "사용자", "기획", "PM"],
            modes: [.plan, .research],
            outputs: [.document, .plan],
            suggestedPersona: "프로젝트 기획 및 관리 전문가. 요구사항 분석, 로드맵 수립, 우선순위 설정을 담당합니다."
        ),
        AgentPreset(
            id: "researcher",
            name: "리서처",
            icon: "magnifyingglass",
            category: .planning,
            tags: ["조사", "분석", "데이터", "트렌드", "경쟁사", "리서치"],
            modes: [.research],
            outputs: [.document, .data],
            suggestedPersona: "리서치 및 데이터 분석 전문가. 시장 조사, 경쟁사 분석, 트렌드 리서치를 담당합니다."
        ),
        AgentPreset(
            id: "content-writer",
            name: "문서/콘텐츠 작성자",
            icon: "doc.text",
            category: .content,
            tags: ["문서", "보고서", "번역", "카피", "블로그", "메일", "이메일"],
            modes: [.create, .review],
            outputs: [.document, .communication, .translation],
            suggestedPersona: "문서 작성 및 콘텐츠 제작 전문가. 보고서, 기술 문서, 이메일, 번역을 담당합니다."
        ),
        AgentPreset(
            id: "marketer",
            name: "마케터",
            icon: "megaphone",
            category: .content,
            tags: ["마케팅", "SNS", "광고", "캠페인", "SEO", "브랜딩"],
            modes: [.create, .plan, .research],
            outputs: [.communication, .document],
            suggestedPersona: "마케팅 전략 및 콘텐츠 제작 전문가. SNS 캠페인, 카피라이팅, SEO를 담당합니다."
        ),
        AgentPreset(
            id: "designer",
            name: "디자이너",
            icon: "paintpalette",
            category: .content,
            tags: ["UI", "UX", "프로토타입", "피그마", "디자인", "레이아웃"],
            modes: [.create, .review],
            outputs: [.document],
            suggestedPersona: "UI/UX 디자인 전문가. 사용자 경험 설계, 프로토타이핑, 비주얼 디자인을 담당합니다."
        ),
        AgentPreset(
            id: "legal",
            name: "법무/컴플라이언스",
            icon: "building.columns",
            category: .operations,
            tags: ["계약", "법률", "규정", "개인정보", "약관", "compliance"],
            modes: [.review, .research],
            outputs: [.review, .document],
            suggestedPersona: "법무 및 컴플라이언스 전문가. 계약서 검토, 규정 준수, 개인정보 보호를 담당합니다."
        ),
        AgentPreset(
            id: "data-analyst",
            name: "데이터 분석가",
            icon: "chart.xyaxis.line",
            category: .planning,
            tags: ["데이터", "sql", "시각화", "통계", "excel", "분석"],
            modes: [.research, .create],
            outputs: [.data, .document],
            suggestedPersona: "데이터 분석 및 시각화 전문가. SQL 쿼리, 통계 분석, 대시보드 생성을 담당합니다."
        ),
        AgentPreset(
            id: "cs-support",
            name: "CS/고객대응",
            icon: "person.wave.2",
            category: .operations,
            tags: ["고객", "CS", "응대", "클레임", "상담", "서비스"],
            modes: [.create, .review],
            outputs: [.communication],
            suggestedPersona: "고객 서비스 및 커뮤니케이션 전문가. 고객 응대, 클레임 처리, 사과문 작성을 담당합니다."
        ),
    ]

    /// 프리셋 ID로 검색
    static func find(_ id: String) -> AgentPreset? {
        builtIn.first { $0.id == id }
    }

    /// 카테고리별 그룹핑 (순서 보존)
    static var grouped: [(category: PresetCategory, presets: [AgentPreset])] {
        PresetCategory.allCases.compactMap { cat in
            let items = builtIn.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }
}
