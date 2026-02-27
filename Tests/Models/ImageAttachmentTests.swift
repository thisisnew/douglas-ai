import Testing
import Foundation
@testable import DOUGLASLib

@Suite("ImageAttachment Tests")
struct ImageAttachmentTests {

    // MARK: - MIME 타입 판별

    @Test("mimeType - JPEG 매직바이트")
    func mimeTypeJPEG() {
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        let data = Data(jpegBytes)
        #expect(ImageAttachment.mimeType(for: data) == "image/jpeg")
    }

    @Test("mimeType - PNG 매직바이트")
    func mimeTypePNG() {
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let data = Data(pngBytes)
        #expect(ImageAttachment.mimeType(for: data) == "image/png")
    }

    @Test("mimeType - GIF 매직바이트")
    func mimeTypeGIF() {
        let gifBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        let data = Data(gifBytes)
        #expect(ImageAttachment.mimeType(for: data) == "image/gif")
    }

    @Test("mimeType - WebP 매직바이트")
    func mimeTypeWebP() {
        // RIFF....WEBP
        let webpBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
        let data = Data(webpBytes)
        #expect(ImageAttachment.mimeType(for: data) == "image/webp")
    }

    @Test("mimeType - 알 수 없는 형식은 nil")
    func mimeTypeUnknown() {
        let randomBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let data = Data(randomBytes)
        #expect(ImageAttachment.mimeType(for: data) == nil)
    }

    @Test("mimeType - 데이터 너무 짧으면 nil")
    func mimeTypeTooShort() {
        let data = Data([0xFF, 0xD8])
        #expect(ImageAttachment.mimeType(for: data) == nil)
    }

    // MARK: - 저장/로드 라운드트립

    @Test("save/loadBase64 라운드트립")
    func saveAndLoadRoundTrip() throws {
        let content = "test image data for round trip"
        let data = Data(content.utf8)
        let attachment = try ImageAttachment.save(data: data, mimeType: "image/png")
        defer { attachment.delete() }

        let base64 = try attachment.loadBase64()
        let decoded = Data(base64Encoded: base64)
        #expect(decoded == data)
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.fileSizeBytes == data.count)
        #expect(attachment.filename.hasSuffix(".png"))
    }

    @Test("save/loadData 라운드트립")
    func saveAndLoadData() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02, 0x03])
        let attachment = try ImageAttachment.save(data: data, mimeType: "image/png")
        defer { attachment.delete() }

        let loaded = try attachment.loadData()
        #expect(loaded == data)
    }

    @Test("delete - 파일 삭제 확인")
    func deleteRemovesFile() throws {
        let data = Data("test".utf8)
        let attachment = try ImageAttachment.save(data: data, mimeType: "image/jpeg")
        #expect(FileManager.default.fileExists(atPath: attachment.diskPath.path))

        attachment.delete()
        #expect(!FileManager.default.fileExists(atPath: attachment.diskPath.path))
    }

    @Test("save - 크기 초과 검증")
    func saveTooLarge() {
        // 21MB 데이터
        let largeData = Data(repeating: 0x00, count: 21 * 1024 * 1024)
        #expect(throws: ImageAttachmentError.self) {
            _ = try ImageAttachment.save(data: largeData, mimeType: "image/png")
        }
    }

    // MARK: - Codable

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let data = Data("codable test".utf8)
        let attachment = try ImageAttachment.save(data: data, mimeType: "image/gif")
        defer { attachment.delete() }

        let encoded = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(ImageAttachment.self, from: encoded)

        #expect(decoded.id == attachment.id)
        #expect(decoded.filename == attachment.filename)
        #expect(decoded.mimeType == "image/gif")
        #expect(decoded.fileSizeBytes == data.count)
    }

    // MARK: - 파일 확장자

    @Test("filename 확장자 - JPEG")
    func filenameExtJPEG() throws {
        let data = Data("test".utf8)
        let att = try ImageAttachment.save(data: data, mimeType: "image/jpeg")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".jpg"))
    }

    @Test("filename 확장자 - WebP")
    func filenameExtWebP() throws {
        let data = Data("test".utf8)
        let att = try ImageAttachment.save(data: data, mimeType: "image/webp")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".webp"))
    }
}
