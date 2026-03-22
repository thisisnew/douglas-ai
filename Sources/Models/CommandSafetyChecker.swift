import Foundation

// MARK: - 사용자 정의 안전 규칙

/// 사용자가 프로젝트별로 지정하는 명령어 차단/확인 규칙
struct SafetyRule: Identifiable, Codable, Hashable {
    let id: UUID
    var pattern: String          // regex 패턴
    var risk: CommandRisk
    var reason: String

    init(id: UUID = UUID(), pattern: String, risk: CommandRisk, reason: String) {
        self.id = id
        self.pattern = pattern
        self.risk = risk
        self.reason = reason
    }
}

// MARK: - 위험도 레벨

enum CommandRisk: String, Codable, Hashable, CaseIterable, Comparable {
    case allow
    case warn
    case confirm
    case block

    private var order: Int {
        switch self {
        case .allow:   return 0
        case .warn:    return 1
        case .confirm: return 2
        case .block:   return 3
        }
    }

    static func < (lhs: CommandRisk, rhs: CommandRisk) -> Bool {
        lhs.order < rhs.order
    }

    var displayName: String {
        switch self {
        case .allow:   return "허용"
        case .warn:    return "경고"
        case .confirm: return "확인 필요"
        case .block:   return "차단"
        }
    }
}

// MARK: - Command Safety Checker

/// 3계층 안전 규칙으로 명령어 위험도를 판정
///
/// 1. 시스템 기본 (하드코딩, 수정 불가)
/// 2. 프로젝트 규칙 (사용자 설정, 코드 레벨 강제)
/// 3. 에이전트 업무 규칙 (프롬프트 레벨 — 별도 처리)
enum CommandSafetyChecker {

    struct Result {
        let risk: CommandRisk
        let reason: String?
    }

    /// 명령어 위험도 검사
    /// - Parameters:
    ///   - command: 실행할 셸 명령어
    ///   - projectRules: 사용자가 지정한 프로젝트 규칙 (기본 빈 배열)
    /// - Returns: 위험도와 사유
    static func check(_ command: String, projectRules: [SafetyRule] = []) -> Result {
        // 1단계: 시스템 기본 BLOCK 규칙 (최우선, 무조건 차단)
        for rule in systemBlockRules {
            if matches(command: command, pattern: rule.pattern) {
                return Result(risk: .block, reason: rule.reason)
            }
        }

        // 2단계: 시스템 기본 CONFIRM 규칙
        var highestRisk: CommandRisk = .allow
        var highestReason: String?

        for rule in systemConfirmRules {
            if matches(command: command, pattern: rule.pattern) {
                if rule.risk > highestRisk {
                    highestRisk = rule.risk
                    highestReason = rule.reason
                }
            }
        }

        // 3단계: 프로젝트 규칙 (시스템 BLOCK보다 낮은 우선순위)
        for rule in projectRules {
            if matches(command: command, pattern: rule.pattern) {
                if rule.risk > highestRisk {
                    highestRisk = rule.risk
                    highestReason = rule.reason
                }
            }
        }

        if highestRisk == .allow {
            return Result(risk: .allow, reason: nil)
        }
        return Result(risk: highestRisk, reason: highestReason)
    }

    // MARK: - Private

    private struct PatternRule {
        let pattern: String
        let risk: CommandRisk
        let reason: String
    }

    private static func matches(command: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // regex 실패 시 단순 문자열 포함으로 폴백
            return command.lowercased().contains(pattern.lowercased())
        }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }

    // MARK: - 시스템 기본 BLOCK 규칙 (절대 수정 불가)

    private static let systemBlockRules: [PatternRule] = [
        // 재귀 삭제 (루트, 홈, 현재 디렉토리)
        PatternRule(pattern: #"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?-[a-zA-Z]*r[a-zA-Z]*\s+[/~.](?:\s|$)"#,
                    risk: .block, reason: "재귀 삭제: 루트/홈/현재 디렉토리 삭제 차단"),
        PatternRule(pattern: #"rm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+)?-[a-zA-Z]*f[a-zA-Z]*\s+[/~.](?:\s|$)"#,
                    risk: .block, reason: "재귀 삭제: 루트/홈/현재 디렉토리 삭제 차단"),

        // 디스크 포맷/덮어쓰기
        PatternRule(pattern: #"mkfs\b"#,
                    risk: .block, reason: "디스크 포맷 명령 차단"),
        PatternRule(pattern: #"dd\s+if="#,
                    risk: .block, reason: "디스크 직접 쓰기 명령 차단"),

        // fork bomb
        PatternRule(pattern: #":\(\)\{.*\|.*&.*\}.*;"#,
                    risk: .block, reason: "fork bomb 차단"),

        // 원격 코드 실행
        PatternRule(pattern: #"curl\s+.*\|\s*(bash|sh|zsh)"#,
                    risk: .block, reason: "원격 스크립트 실행 차단"),
        PatternRule(pattern: #"wget\s+.*\|\s*(bash|sh|zsh)"#,
                    risk: .block, reason: "원격 스크립트 실행 차단"),

        // DB 파괴
        PatternRule(pattern: #"DROP\s+(TABLE|DATABASE)\b"#,
                    risk: .block, reason: "데이터베이스 삭제 명령 차단"),

        // 시스템 종료
        PatternRule(pattern: #"\b(shutdown|reboot|halt)\b"#,
                    risk: .block, reason: "시스템 종료/재부팅 명령 차단"),

        // 권한 전체 파괴
        PatternRule(pattern: #"chmod\s+-R\s+(777|000)\b"#,
                    risk: .block, reason: "재귀 권한 변경(777/000) 차단"),
    ]

    // MARK: - 시스템 기본 CONFIRM 규칙

    private static let systemConfirmRules: [PatternRule] = [
        // 재귀 삭제 (특정 경로)
        PatternRule(pattern: #"rm\s+.*-[a-zA-Z]*r"#,
                    risk: .confirm, reason: "재귀 삭제 명령 — 확인 필요"),

        // 강제 푸시
        PatternRule(pattern: #"git\s+push\s+.*--force"#,
                    risk: .confirm, reason: "강제 푸시 — 확인 필요"),
        PatternRule(pattern: #"git\s+push\s+-f\b"#,
                    risk: .confirm, reason: "강제 푸시 — 확인 필요"),

        // sudo
        PatternRule(pattern: #"\bsudo\b"#,
                    risk: .confirm, reason: "관리자 권한 명령 — 확인 필요"),

        // git reset --hard
        PatternRule(pattern: #"git\s+reset\s+--hard"#,
                    risk: .confirm, reason: "하드 리셋 — 확인 필요"),
    ]
}
