import Foundation
import AppKit
import UniformTypeIdentifiers

/// 문서 산출물을 파일로 내보내기
@MainActor
enum DocumentExporter {

    /// 문서 내용을 파일로 저장 (NSSavePanel)
    /// - Returns: 저장된 파일 URL (nil = 사용자 취소 또는 오류)
    @discardableResult
    static func saveDocument(
        content: String,
        suggestedName: String,
        defaultExtension: String = "md"
    ) -> URL? {
        let panel = NSSavePanel()

        var allowedTypes: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { allowedTypes.insert(md, at: 0) }
        allowedTypes.append(.html)
        panel.allowedContentTypes = allowedTypes

        panel.nameFieldStringValue = sanitizeFilename(suggestedName, ext: defaultExtension)
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

    /// 방에서 문서 내용 추출 (artifact 우선, fallback: 마지막 assistant 메시지)
    static func extractDocumentContent(from room: Room) -> String? {
        // 1차: artifact type == .document (최신 버전 우선)
        if let docArtifact = room.artifacts
            .filter({ $0.type == .document })
            .sorted(by: { $0.version > $1.version })
            .first {
            return ArtifactParser.stripArtifactBlocks(from: docArtifact.content)
        }

        // 2차: 마지막 assistant .text 메시지
        if let lastMsg = room.messages
            .reversed()
            .first(where: { $0.role == .assistant && $0.messageType == .text }) {
            return ArtifactParser.stripArtifactBlocks(from: lastMsg.content)
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
