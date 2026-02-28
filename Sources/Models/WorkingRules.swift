import Foundation

/// 작업 규칙 소스 — 에이전트가 작업 시 준수해야 할 구체적 지시사항
enum WorkingRulesSource: Codable, Equatable {
    case inline(String)      // 직접 입력한 텍스트 규칙
    case filePath(String)    // 파일 경로 참조 (예: .cursorrules)

    /// 실행 시점에 규칙 텍스트를 resolve
    /// - inline: 그대로 반환
    /// - filePath: 파일을 읽어서 반환 (실패 시 경고 메시지)
    func resolve() -> String {
        switch self {
        case .inline(let text):
            return text
        case .filePath(let path):
            let expandedPath = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath),
                  let content = try? String(contentsOfFile: expandedPath, encoding: .utf8),
                  !content.isEmpty else {
                return "[경고: 규칙 파일을 읽을 수 없습니다 — \(path)]"
            }
            return content
        }
    }

    /// UI 표시용 요약
    var displaySummary: String {
        switch self {
        case .inline(let text):
            let preview = text.prefix(80)
            return text.count > 80 ? "\(preview)..." : String(preview)
        case .filePath(let path):
            return "파일: \((path as NSString).lastPathComponent)"
        }
    }

    var isEmpty: Bool {
        switch self {
        case .inline(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .filePath(let path): return path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
