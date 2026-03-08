import Foundation

/// 업무 규칙 레코드 — 에이전트의 개별 규칙 단위
/// 이름/요약으로 태스크 매칭, 상세 내용은 실행 시 resolve
struct WorkRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String            // "코딩 규칙", "PR 규칙"
    var summary: String         // 매칭에 사용되는 키워드 포함 요약 (1-2줄)
    var content: WorkRuleContent
    var isAlwaysActive: Bool    // true면 매칭 없이 항상 포함

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        content: WorkRuleContent,
        isAlwaysActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.content = content
        self.isAlwaysActive = isAlwaysActive
    }

    /// 실행 시점에 규칙 텍스트 resolve
    func resolve() -> String {
        switch content {
        case .inline(let text):
            return text

        case .file(let path):
            let expandedPath = NSString(string: path).expandingTildeInPath
            let maxFileBytes = 100_000  // 100KB 제한
            if let attrs = try? FileManager.default.attributesOfItem(atPath: expandedPath),
               let size = attrs[.size] as? Int, size > maxFileBytes {
                return "[경고: 규칙 파일이 너무 큽니다 (\(size / 1024)KB > \(maxFileBytes / 1024)KB) — \(path)]"
            }
            guard FileManager.default.fileExists(atPath: expandedPath),
                  let text = try? String(contentsOfFile: expandedPath, encoding: .utf8),
                  !text.isEmpty else {
                return "[경고: 규칙 파일을 읽을 수 없습니다 — \(path)]"
            }
            return text
        }
    }

    /// UI 표시용 요약
    var displaySummary: String {
        let preview = summary.prefix(80)
        let suffix = summary.count > 80 ? "..." : ""
        return "\(name): \(preview)\(suffix)"
    }

    /// 내용이 비어있는지 확인
    var isEmpty: Bool {
        switch content {
        case .inline(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file(let path):
            return path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - 규칙 내용 유형

enum WorkRuleContent: Codable, Equatable {
    case inline(String)
    case file(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, path
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inline(let text):
            try container.encode("inline", forKey: .type)
            try container.encode(text, forKey: .text)
        case .file(let path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "inline":
            let text = try container.decode(String.self, forKey: .text)
            self = .inline(text)
        case "file":
            let path = try container.decode(String.self, forKey: .path)
            self = .file(path)
        default:
            self = .inline("")
        }
    }
}
