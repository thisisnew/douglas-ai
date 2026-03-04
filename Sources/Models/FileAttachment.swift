import Foundation

/// 채팅 메시지에 첨부할 파일 (이미지 + 문서)
struct FileAttachment: Codable, Identifiable {
    let id: UUID
    let filename: String            // UUID.ext (디스크 저장용)
    let originalFilename: String?   // 사용자가 선택한 원래 파일 이름 (표시용)
    let mimeType: String            // "image/jpeg", "application/pdf" 등
    let fileSizeBytes: Int

    /// 이미지 파일 여부
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    /// 표시용 파일 이름 (originalFilename 우선)
    var displayName: String {
        originalFilename ?? filename
    }

    /// 파일 타입별 SF Symbol 아이콘
    var fileIcon: String {
        if isImage { return "photo" }
        switch mimeType {
        case "application/pdf":                                      return "doc.richtext"
        case "text/plain":                                           return "doc.text"
        case "text/csv":                                             return "tablecells"
        case "application/json":                                     return "curlybraces"
        case "text/markdown":                                        return "doc.text"
        case "application/xml":                                      return "chevron.left.forwardslash.chevron.right"
        case "text/yaml":                                            return "doc.text"
        case "text/html":                                            return "globe"
        case "text/css":                                             return "paintbrush"
        case "application/javascript", "application/typescript":     return "chevron.left.forwardslash.chevron.right"
        case "text/x-swift":                                         return "swift"
        case "text/x-python":                                        return "chevron.left.forwardslash.chevron.right"
        case "text/x-shellscript":                                   return "terminal"
        default:                                                     return "doc"
        }
    }

    // MARK: - Codable (하위 호환)

    enum CodingKeys: String, CodingKey {
        case id, filename, originalFilename, mimeType, fileSizeBytes
    }

    init(id: UUID, filename: String, originalFilename: String? = nil, mimeType: String, fileSizeBytes: Int) {
        self.id = id
        self.filename = filename
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        originalFilename = try container.decodeIfPresent(String.self, forKey: .originalFilename)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        fileSizeBytes = try container.decode(Int.self, forKey: .fileSizeBytes)
    }

    // MARK: - 디스크 저장 경로

    private static var attachmentsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agentmanager")
        let dir = appSupport.appendingPathComponent("DOUGLAS/attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var diskPath: URL {
        Self.attachmentsDir.appendingPathComponent(filename)
    }

    // MARK: - 저장 / 로드

    /// 파일 데이터를 디스크에 저장하고 FileAttachment 반환
    static func save(data: Data, mimeType: String, originalFilename: String? = nil) throws -> FileAttachment {
        let maxSize = 20 * 1024 * 1024 // 20MB
        guard data.count <= maxSize else {
            throw FileAttachmentError.fileTooLarge(data.count)
        }

        let ext = Self.fileExtension(for: mimeType)
        let id = UUID()
        let diskFilename = "\(id.uuidString).\(ext)"
        let attachment = FileAttachment(
            id: id,
            filename: diskFilename,
            originalFilename: originalFilename,
            mimeType: mimeType,
            fileSizeBytes: data.count
        )
        try data.write(to: attachment.diskPath)
        return attachment
    }

    /// 디스크에서 base64 인코딩된 데이터 로드
    func loadBase64() throws -> String {
        let data = try Data(contentsOf: diskPath)
        return data.base64EncodedString()
    }

    /// 디스크에서 원본 데이터 로드
    func loadData() throws -> Data {
        try Data(contentsOf: diskPath)
    }

    /// 텍스트 기반 파일이면 UTF-8 문자열로 로드
    func loadTextContent() -> String? {
        guard !isImage && mimeType != "application/pdf" else { return nil }
        guard let data = try? loadData(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// 디스크 파일 삭제
    func delete() {
        try? FileManager.default.removeItem(at: diskPath)
    }

    // MARK: - MIME 타입 판별

    /// 매직바이트로 MIME 타입 판별 (이미지 + PDF)
    static func mimeType(for data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(12))

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }
        // PNG: 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        // GIF: 47 49 46 38
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return "image/gif"
        }
        // WebP: RIFF....WEBP
        if data.count >= 12 &&
           bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "image/webp"
        }
        // PDF: %PDF (25 50 44 46)
        if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return "application/pdf"
        }

        return nil
    }

    /// 파일 확장자로 MIME 타입 판별 (텍스트 기반 파일)
    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "txt":                return "text/plain"
        case "csv":                return "text/csv"
        case "json":               return "application/json"
        case "md", "markdown":     return "text/markdown"
        case "xml":                return "application/xml"
        case "yaml", "yml":        return "text/yaml"
        case "html", "htm":        return "text/html"
        case "css":                return "text/css"
        case "js":                 return "application/javascript"
        case "ts":                 return "application/typescript"
        case "swift":              return "text/x-swift"
        case "py":                 return "text/x-python"
        case "sh", "bash", "zsh":  return "text/x-shellscript"
        default:                   return nil
        }
    }

    /// 파일 URL에서 MIME 타입 판별: 매직바이트 우선, 실패 시 확장자 판별
    static func detectMimeType(for url: URL, data: Data) -> String? {
        if let mime = mimeType(for: data) {
            return mime
        }
        return mimeType(forExtension: url.pathExtension)
    }

    // MARK: - 헬퍼

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg":                return "jpg"
        case "image/png":                 return "png"
        case "image/gif":                 return "gif"
        case "image/webp":                return "webp"
        case "application/pdf":           return "pdf"
        case "text/plain":                return "txt"
        case "text/csv":                  return "csv"
        case "application/json":          return "json"
        case "text/markdown":             return "md"
        case "application/xml":           return "xml"
        case "text/yaml":                 return "yaml"
        case "text/html":                 return "html"
        case "text/css":                  return "css"
        case "application/javascript":    return "js"
        case "application/typescript":    return "ts"
        case "text/x-swift":             return "swift"
        case "text/x-python":            return "py"
        case "text/x-shellscript":       return "sh"
        default:                          return "dat"
        }
    }

    /// 파일 크기 포맷
    static func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - 하위 호환 별칭

typealias ImageAttachment = FileAttachment

// MARK: - 오류

enum FileAttachmentError: LocalizedError {
    case fileTooLarge(Int)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            return "파일이 너무 큽니다 (\(size / 1024 / 1024)MB). 최대 20MB까지 허용됩니다."
        case .unsupportedFormat:
            return "지원하지 않는 파일 형식입니다."
        }
    }
}

typealias ImageAttachmentError = FileAttachmentError
