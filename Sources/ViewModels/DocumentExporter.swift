import Foundation
import AppKit
import UniformTypeIdentifiers

/// 문서 산출물을 파일로 내보내기
@MainActor
enum DocumentExporter {

    /// 문서 내용을 파일로 저장
    /// - 고정 경로 설정 시: 해당 폴더에 자동 저장 (NSSavePanel 없음)
    /// - 미설정 시: NSSavePanel으로 위치 선택
    /// - Returns: 저장된 파일 URL (nil = 사용자 취소 또는 오류)
    @discardableResult
    static func saveDocument(
        content: String,
        suggestedName: String,
        defaultExtension: String = "md"
    ) -> URL? {
        let filename = sanitizeFilename(suggestedName, ext: defaultExtension)

        // 고정 경로가 설정되어 있으면 자동 저장
        if let fixedDir = UserDefaults.standard.string(forKey: "documentSaveDirectory"),
           !fixedDir.isEmpty,
           {
               var isDir: ObjCBool = false
               return FileManager.default.fileExists(atPath: fixedDir, isDirectory: &isDir) && isDir.boolValue
           }() {
            let dirURL = URL(fileURLWithPath: fixedDir)
            let fileURL = uniqueFileURL(directory: dirURL, filename: filename)
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return fileURL
            } catch {
                // 자동 저장 실패 시 NSSavePanel 폴백
            }
        }

        // NSSavePanel으로 위치 선택
        let panel = NSSavePanel()

        var allowedTypes: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { allowedTypes.insert(md, at: 0) }
        allowedTypes.append(.html)
        panel.allowedContentTypes = allowedTypes

        panel.nameFieldStringValue = filename
        panel.message = "문서를 저장할 위치를 선택하세요"
        panel.prompt = "저장"

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = docsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// 같은 이름의 파일이 있으면 (2), (3)... 을 붙여 고유 파일명 생성
    private static func uniqueFileURL(directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// 방에서 문서 내용 추출 (artifact 우선, fallback: 마지막 assistant 메시지)
    static func extractDocumentContent(from room: Room) -> String? {
        // 1차: artifact type == .document (최신 버전 우선)
        if let docArtifact = room.artifacts
            .filter({ $0.type == .document })
            .sorted(by: { $0.version > $1.version })
            .first {
            return ArtifactParser.stripArtifactBlocks(from: docArtifact.content)
        }

        // 2차: 마지막 assistant .text 메시지 (최소 200자 이상이어야 문서로 간주)
        if let lastMsg = room.messages
            .reversed()
            .first(where: { $0.role == .assistant && $0.messageType == .text }) {
            let content = ArtifactParser.stripArtifactBlocks(from: lastMsg.content)
            if content.count >= 200 { return content }
        }

        return nil
    }

    /// 방의 메시지에서 에이전트가 실제 생성한 문서 파일 경로 추출
    /// - 1차: toolActivity의 file_write/Write 기록
    /// - 2차: 어시스턴트 텍스트에서 절대 경로 언급 탐색 (backtick 감싸진 패턴)
    static func findActualDocumentFile(from room: Room) -> URL? {
        let docExtensions: Set<String> = ["pdf", "docx", "xlsx", "html", "pptx", "csv", "txt"]

        // 1차: toolActivity에서 file_write/Write 경로 (최신 순)
        for msg in room.messages.reversed() where msg.messageType == .toolActivity {
            guard let detail = msg.toolDetail,
                  ["file_write", "Write"].contains(detail.toolName),
                  let path = detail.subject else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            if docExtensions.contains(ext),
               FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2차: 어시스턴트 메시지에서 backtick 감싸진 절대 경로 추출
        guard let regex = try? NSRegularExpression(
            pattern: "`(/[^`\\n]+\\.(?:pdf|docx|xlsx|html|pptx|csv))`",
            options: []
        ) else { return nil }

        for msg in room.messages.reversed() where msg.role == .assistant && msg.messageType == .text {
            let nsStr = msg.content as NSString
            let matches = regex.matches(in: msg.content, options: [], range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let path = nsStr.substring(with: match.range(at: 1))
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        return nil
    }

    /// 방 정보로 제안 파일명 생성
    static func suggestedFilename(room: Room) -> String {
        if let docType = room.documentType, docType != .freeform {
            return "\(docType.displayName) - \(room.title)"
        }
        return room.title
    }

    /// 파일명에서 특수문자 제거
    static func sanitizeFilename(_ name: String, ext: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet.alphanumerics
                .union(.init(charactersIn: " _-"))
                .union(CharacterSet(charactersIn: "\u{AC00}"..."\u{D7A3}"))  // 완성형 한글
                .union(CharacterSet(charactersIn: "\u{3131}"..."\u{3163}"))  // 한글 자모
                .inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "document" : cleaned
        let truncated = String(base.prefix(80))
        return "\(truncated).\(ext)"
    }
}
