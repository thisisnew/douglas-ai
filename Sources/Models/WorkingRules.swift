import Foundation

/// 작업 규칙 소스 — 에이전트가 작업 시 준수해야 할 구체적 지시사항
/// 인라인 텍스트와 파일 참조를 동시에 사용 가능
struct WorkingRulesSource: Codable, Equatable {
    var inlineText: String
    var filePaths: [String]

    static let empty = WorkingRulesSource(inlineText: "", filePaths: [])

    /// 실행 시점에 규칙 텍스트를 resolve (인라인 + 파일 내용 합산)
    func resolve() -> String {
        var parts: [String] = []

        let trimmedInline = inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInline.isEmpty {
            parts.append(inlineText)
        }

        let maxFileBytes = 100_000  // 100KB 제한 — 시스템 프롬프트 폭증 방지
        for path in filePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            // 파일 크기 확인 — 대용량 파일 로드 방지
            if let attrs = try? FileManager.default.attributesOfItem(atPath: expandedPath),
               let size = attrs[.size] as? Int, size > maxFileBytes {
                parts.append("[경고: 규칙 파일이 너무 큽니다 (\(size / 1024)KB > \(maxFileBytes / 1024)KB) — \(path)]")
                continue
            }
            guard FileManager.default.fileExists(atPath: expandedPath),
                  let content = try? String(contentsOfFile: expandedPath, encoding: .utf8),
                  !content.isEmpty else {
                parts.append("[경고: 규칙 파일을 읽을 수 없습니다 — \(path)]")
                continue
            }
            parts.append(content)
        }

        return parts.joined(separator: "\n\n")
    }

    /// 우선순위 마커 기반으로 규칙을 분류
    /// [필수] → critical, [중요] → important, 마커 없음 → normal
    struct PrioritizedRules: Equatable {
        var critical: [String] = []   // [필수]
        var important: [String] = []  // [중요]
        var normal: [String] = []     // 마커 없음
    }

    /// resolve된 텍스트를 우선순위별로 분류
    func prioritize() -> PrioritizedRules {
        let text = resolve()
        guard !text.isEmpty else { return PrioritizedRules() }

        var result = PrioritizedRules()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // "- [필수] ...", "[필수] ...", "- [필수]..." 등 유연하게 매칭
            let stripped = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) : trimmed

            if stripped.hasPrefix("[필수]") {
                let content = stripped.dropFirst("[필수]".count).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { result.critical.append(content) }
            } else if stripped.hasPrefix("[중요]") {
                let content = stripped.dropFirst("[중요]".count).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { result.important.append(content) }
            } else {
                // 마커 없는 줄: "- " 접두사 제거 후 저장
                let content = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) : trimmed
                result.normal.append(content)
            }
        }
        return result
    }

    /// 우선순위별로 분류된 시스템 프롬프트용 텍스트 생성
    func resolveWithPriority() -> String {
        let p = prioritize()
        let hasPriorityMarkers = !p.critical.isEmpty || !p.important.isEmpty

        // 마커를 하나도 안 쓴 경우 — 기존 동작 (평면 출력)
        guard hasPriorityMarkers else {
            return resolve()
        }

        var sections: [String] = []

        if !p.critical.isEmpty {
            let items = p.critical.map { "- \($0)" }.joined(separator: "\n")
            sections.append("### [절대 규칙 — 위반 시 작업 실패]\n\(items)")
        }
        if !p.important.isEmpty {
            let items = p.important.map { "- \($0)" }.joined(separator: "\n")
            sections.append("### [중요 규칙]\n\(items)")
        }
        if !p.normal.isEmpty {
            let items = p.normal.map { "- \($0)" }.joined(separator: "\n")
            sections.append("### [일반 규칙]\n\(items)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// UI 표시용 요약
    var displaySummary: String {
        var summaries: [String] = []

        let trimmedInline = inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInline.isEmpty {
            let preview = trimmedInline.prefix(60)
            summaries.append(trimmedInline.count > 60 ? "\(preview)..." : String(preview))
        }

        if !filePaths.isEmpty {
            let names = filePaths.map { ($0 as NSString).lastPathComponent }
            summaries.append("파일: \(names.joined(separator: ", "))")
        }

        return summaries.joined(separator: " + ")
    }

    var isEmpty: Bool {
        inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filePaths.isEmpty
    }

    // MARK: - 레거시 호환 Codable

    private enum CodingKeys: String, CodingKey {
        case inlineText, filePaths
        // 레거시
        case type, inline, filePath
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inlineText, forKey: .inlineText)
        try container.encode(filePaths, forKey: .filePaths)
    }

    init(inlineText: String = "", filePaths: [String] = []) {
        self.inlineText = inlineText
        self.filePaths = filePaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 새 포맷: {"inlineText": "...", "filePaths": [...]}
        if let text = try? container.decode(String.self, forKey: .inlineText) {
            inlineText = text
            filePaths = (try? container.decode([String].self, forKey: .filePaths)) ?? []
            return
        }

        // 레거시 enum 포맷: {"type": "inline|filePath|filePaths", ...}
        if let type = try? container.decode(String.self, forKey: .type) {
            switch type {
            case "inline":
                inlineText = (try? container.decode(String.self, forKey: .inline)) ?? ""
                filePaths = []
            case "filePath":
                inlineText = ""
                let path = (try? container.decode(String.self, forKey: .filePath)) ?? ""
                filePaths = path.isEmpty ? [] : [path]
            case "filePaths":
                inlineText = ""
                filePaths = (try? container.decode([String].self, forKey: .filePaths)) ?? []
            default:
                inlineText = ""
                filePaths = []
            }
            return
        }

        inlineText = ""
        filePaths = []
    }
}
