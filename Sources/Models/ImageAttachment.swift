import Foundation

/// 채팅 메시지에 첨부할 이미지
struct ImageAttachment: Codable, Identifiable {
    let id: UUID
    let filename: String        // UUID.ext
    let mimeType: String        // "image/jpeg" 등
    let fileSizeBytes: Int

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

    /// 이미지 데이터를 디스크에 저장하고 ImageAttachment 반환
    static func save(data: Data, mimeType: String) throws -> ImageAttachment {
        let maxSize = 20 * 1024 * 1024 // 20MB
        guard data.count <= maxSize else {
            throw ImageAttachmentError.fileTooLarge(data.count)
        }

        let ext = Self.fileExtension(for: mimeType)
        let id = UUID()
        let filename = "\(id.uuidString).\(ext)"
        let attachment = ImageAttachment(
            id: id,
            filename: filename,
            mimeType: mimeType,
            fileSizeBytes: data.count
        )
        try data.write(to: attachment.diskPath)
        return attachment
    }

    /// 디스크에서 base64 인코딩된 이미지 데이터 로드
    func loadBase64() throws -> String {
        let data = try Data(contentsOf: diskPath)
        return data.base64EncodedString()
    }

    /// 디스크에서 원본 데이터 로드
    func loadData() throws -> Data {
        try Data(contentsOf: diskPath)
    }

    /// 디스크 파일 삭제
    func delete() {
        try? FileManager.default.removeItem(at: diskPath)
    }

    // MARK: - MIME 타입 판별

    /// 매직바이트로 MIME 타입 판별
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

        return nil
    }

    // MARK: - 헬퍼

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/png":  return "png"
        case "image/gif":  return "gif"
        case "image/webp": return "webp"
        default:           return "dat"
        }
    }
}

// MARK: - 오류

enum ImageAttachmentError: LocalizedError {
    case fileTooLarge(Int)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            return "이미지가 너무 큽니다 (\(size / 1024 / 1024)MB). 최대 20MB까지 허용됩니다."
        case .unsupportedFormat:
            return "지원하지 않는 이미지 형식입니다. JPEG, PNG, GIF, WebP만 지원합니다."
        }
    }
}
