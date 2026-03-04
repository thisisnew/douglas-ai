import Testing
import Foundation
@testable import DOUGLAS

@Suite("FileAttachment Tests")
struct FileAttachmentTests {

    // MARK: - MIME 타입 판별 (매직바이트)

    @Test("mimeType - JPEG 매직바이트")
    func mimeTypeJPEG() {
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        let data = Data(jpegBytes)
        #expect(FileAttachment.mimeType(for: data) == "image/jpeg")
    }

    @Test("mimeType - PNG 매직바이트")
    func mimeTypePNG() {
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let data = Data(pngBytes)
        #expect(FileAttachment.mimeType(for: data) == "image/png")
    }

    @Test("mimeType - GIF 매직바이트")
    func mimeTypeGIF() {
        let gifBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        let data = Data(gifBytes)
        #expect(FileAttachment.mimeType(for: data) == "image/gif")
    }

    @Test("mimeType - WebP 매직바이트")
    func mimeTypeWebP() {
        let webpBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
        let data = Data(webpBytes)
        #expect(FileAttachment.mimeType(for: data) == "image/webp")
    }

    @Test("mimeType - PDF 매직바이트")
    func mimeTypePDF() {
        let pdfBytes: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E]
        let data = Data(pdfBytes)
        #expect(FileAttachment.mimeType(for: data) == "application/pdf")
    }

    @Test("mimeType - 알 수 없는 형식은 nil")
    func mimeTypeUnknown() {
        let randomBytes: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let data = Data(randomBytes)
        #expect(FileAttachment.mimeType(for: data) == nil)
    }

    @Test("mimeType - 데이터 너무 짧으면 nil")
    func mimeTypeTooShort() {
        let data = Data([0xFF, 0xD8])
        #expect(FileAttachment.mimeType(for: data) == nil)
    }

    // MARK: - MIME 타입 판별 (확장자)

    @Test("mimeType(forExtension:) - 텍스트 파일들")
    func mimeTypeForExtension() {
        #expect(FileAttachment.mimeType(forExtension: "txt") == "text/plain")
        #expect(FileAttachment.mimeType(forExtension: "csv") == "text/csv")
        #expect(FileAttachment.mimeType(forExtension: "json") == "application/json")
        #expect(FileAttachment.mimeType(forExtension: "md") == "text/markdown")
        #expect(FileAttachment.mimeType(forExtension: "swift") == "text/x-swift")
        #expect(FileAttachment.mimeType(forExtension: "py") == "text/x-python")
        #expect(FileAttachment.mimeType(forExtension: "sh") == "text/x-shellscript")
        #expect(FileAttachment.mimeType(forExtension: "yaml") == "text/yaml")
        #expect(FileAttachment.mimeType(forExtension: "yml") == "text/yaml")
        #expect(FileAttachment.mimeType(forExtension: "html") == "text/html")
        #expect(FileAttachment.mimeType(forExtension: "js") == "application/javascript")
        #expect(FileAttachment.mimeType(forExtension: "ts") == "application/typescript")
        #expect(FileAttachment.mimeType(forExtension: "unknown") == nil)
    }

    // MARK: - detectMimeType 통합 판별

    @Test("detectMimeType - 매직바이트 우선, 확장자 fallback")
    func detectMimeType() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let pngURL = URL(fileURLWithPath: "/tmp/test.png")
        #expect(FileAttachment.detectMimeType(for: pngURL, data: pngBytes) == "image/png")

        let textData = Data("hello world".utf8)
        let txtURL = URL(fileURLWithPath: "/tmp/file.txt")
        #expect(FileAttachment.detectMimeType(for: txtURL, data: textData) == "text/plain")

        let unknownURL = URL(fileURLWithPath: "/tmp/file.xyz")
        #expect(FileAttachment.detectMimeType(for: unknownURL, data: textData) == nil)
    }

    // MARK: - isImage 프로퍼티

    @Test("isImage - 이미지 vs 문서")
    func isImageProperty() throws {
        let imgAtt = try FileAttachment.save(data: Data("img".utf8), mimeType: "image/png")
        defer { imgAtt.delete() }
        #expect(imgAtt.isImage == true)

        let pdfAtt = try FileAttachment.save(data: Data("pdf".utf8), mimeType: "application/pdf")
        defer { pdfAtt.delete() }
        #expect(pdfAtt.isImage == false)

        let txtAtt = try FileAttachment.save(data: Data("txt".utf8), mimeType: "text/plain")
        defer { txtAtt.delete() }
        #expect(txtAtt.isImage == false)
    }

    // MARK: - displayName 프로퍼티

    @Test("displayName - originalFilename 우선, 없으면 filename")
    func displayNameProperty() throws {
        let att1 = try FileAttachment.save(data: Data("a".utf8), mimeType: "text/plain", originalFilename: "readme.txt")
        defer { att1.delete() }
        #expect(att1.displayName == "readme.txt")

        let att2 = try FileAttachment.save(data: Data("b".utf8), mimeType: "text/plain")
        defer { att2.delete() }
        #expect(att2.displayName == att2.filename)
    }

    // MARK: - fileIcon 프로퍼티

    @Test("fileIcon - 타입별 SF Symbol")
    func fileIconProperty() throws {
        let img = try FileAttachment.save(data: Data("x".utf8), mimeType: "image/png")
        defer { img.delete() }
        #expect(img.fileIcon == "photo")

        let pdf = try FileAttachment.save(data: Data("x".utf8), mimeType: "application/pdf")
        defer { pdf.delete() }
        #expect(pdf.fileIcon == "doc.richtext")

        let txt = try FileAttachment.save(data: Data("x".utf8), mimeType: "text/plain")
        defer { txt.delete() }
        #expect(txt.fileIcon == "doc.text")

        let json = try FileAttachment.save(data: Data("x".utf8), mimeType: "application/json")
        defer { json.delete() }
        #expect(json.fileIcon == "curlybraces")

        let sw = try FileAttachment.save(data: Data("x".utf8), mimeType: "text/x-swift")
        defer { sw.delete() }
        #expect(sw.fileIcon == "swift")
    }

    // MARK: - loadTextContent

    @Test("loadTextContent - 텍스트 파일은 내용 반환, 이미지/PDF는 nil")
    func loadTextContentTest() throws {
        let textContent = "Hello, World!"
        let txtAtt = try FileAttachment.save(data: Data(textContent.utf8), mimeType: "text/plain")
        defer { txtAtt.delete() }
        #expect(txtAtt.loadTextContent() == textContent)

        let imgAtt = try FileAttachment.save(data: Data("img".utf8), mimeType: "image/png")
        defer { imgAtt.delete() }
        #expect(imgAtt.loadTextContent() == nil)

        let pdfAtt = try FileAttachment.save(data: Data("pdf".utf8), mimeType: "application/pdf")
        defer { pdfAtt.delete() }
        #expect(pdfAtt.loadTextContent() == nil)
    }

    // MARK: - formatFileSize

    @Test("formatFileSize - 크기 포맷")
    func formatFileSizeTest() {
        #expect(FileAttachment.formatFileSize(500) == "500 B")
        #expect(FileAttachment.formatFileSize(2048) == "2 KB")
        #expect(FileAttachment.formatFileSize(1_500_000) == "1.4 MB")
    }

    // MARK: - 저장/로드 라운드트립

    @Test("save/loadBase64 라운드트립")
    func saveAndLoadRoundTrip() throws {
        let content = "test image data for round trip"
        let data = Data(content.utf8)
        let attachment = try FileAttachment.save(data: data, mimeType: "image/png")
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
        let attachment = try FileAttachment.save(data: data, mimeType: "image/png")
        defer { attachment.delete() }

        let loaded = try attachment.loadData()
        #expect(loaded == data)
    }

    @Test("save - originalFilename 저장 확인")
    func saveWithOriginalFilename() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "text/plain", originalFilename: "report.txt")
        defer { att.delete() }
        #expect(att.originalFilename == "report.txt")
        #expect(att.displayName == "report.txt")
    }

    @Test("delete - 파일 삭제 확인")
    func deleteRemovesFile() throws {
        let data = Data("test".utf8)
        let attachment = try FileAttachment.save(data: data, mimeType: "image/jpeg")
        #expect(FileManager.default.fileExists(atPath: attachment.diskPath.path))

        attachment.delete()
        #expect(!FileManager.default.fileExists(atPath: attachment.diskPath.path))
    }

    @Test("save - 크기 초과 검증")
    func saveTooLarge() {
        let largeData = Data(repeating: 0x00, count: 21 * 1024 * 1024)
        #expect(throws: FileAttachmentError.self) {
            _ = try FileAttachment.save(data: largeData, mimeType: "image/png")
        }
    }

    // MARK: - Codable

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let data = Data("codable test".utf8)
        let attachment = try FileAttachment.save(data: data, mimeType: "image/gif")
        defer { attachment.delete() }

        let encoded = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(FileAttachment.self, from: encoded)

        #expect(decoded.id == attachment.id)
        #expect(decoded.filename == attachment.filename)
        #expect(decoded.mimeType == "image/gif")
        #expect(decoded.fileSizeBytes == data.count)
    }

    @Test("Codable - originalFilename 포함 라운드트립")
    func codableWithOriginalFilename() throws {
        let att = try FileAttachment.save(data: Data("x".utf8), mimeType: "application/pdf", originalFilename: "doc.pdf")
        defer { att.delete() }

        let encoded = try JSONEncoder().encode(att)
        let decoded = try JSONDecoder().decode(FileAttachment.self, from: encoded)
        #expect(decoded.originalFilename == "doc.pdf")
    }

    @Test("Codable - originalFilename 없는 이전 데이터 하위 호환")
    func codableBackwardCompatibility() throws {
        // originalFilename 필드가 없는 JSON (이전 버전 데이터)
        let json = """
        {"id":"12345678-1234-1234-1234-123456789ABC","filename":"test.png","mimeType":"image/png","fileSizeBytes":100}
        """
        let decoded = try JSONDecoder().decode(FileAttachment.self, from: Data(json.utf8))
        #expect(decoded.originalFilename == nil)
        #expect(decoded.displayName == "test.png")
        #expect(decoded.mimeType == "image/png")
    }

    // MARK: - 파일 확장자

    @Test("filename 확장자 - JPEG")
    func filenameExtJPEG() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/jpeg")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".jpg"))
    }

    @Test("filename 확장자 - WebP")
    func filenameExtWebP() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/webp")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".webp"))
    }

    @Test("filename 확장자 - GIF")
    func filenameExtGIF() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/gif")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".gif"))
    }

    @Test("filename 확장자 - PDF")
    func filenameExtPDF() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "application/pdf")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".pdf"))
    }

    @Test("filename 확장자 - TXT")
    func filenameExtTXT() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "text/plain")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".txt"))
    }

    @Test("filename 확장자 - JSON")
    func filenameExtJSON() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "application/json")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".json"))
    }

    @Test("filename 확장자 - 알 수 없는 타입 → .dat")
    func filenameExtUnknown() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "application/octet-stream")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".dat"))
    }

    @Test("filename 확장자 - PNG")
    func filenameExtPNG() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/png")
        defer { att.delete() }
        #expect(att.filename.hasSuffix(".png"))
    }

    // MARK: - diskPath

    @Test("diskPath - attachments 디렉토리 포함")
    func diskPathContainsDir() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/png")
        defer { att.delete() }
        #expect(att.diskPath.path.contains("attachments"))
    }

    // MARK: - 에러 타입

    @Test("FileAttachmentError.fileTooLarge - 에러 설명")
    func errorFileTooLarge() {
        let error = FileAttachmentError.fileTooLarge(25 * 1024 * 1024)
        #expect(error.localizedDescription.contains("25"))
        #expect(error.localizedDescription.contains("20MB"))
    }

    @Test("FileAttachmentError.unsupportedFormat - 에러 설명")
    func errorUnsupportedFormat() {
        let error = FileAttachmentError.unsupportedFormat
        #expect(error.localizedDescription.contains("지원하지 않는"))
    }

    // MARK: - 빈 데이터

    @Test("save - 빈 데이터도 저장 가능")
    func saveEmptyData() throws {
        let att = try FileAttachment.save(data: Data(), mimeType: "image/png")
        defer { att.delete() }
        #expect(att.fileSizeBytes == 0)
        let loaded = try att.loadData()
        #expect(loaded.isEmpty)
    }

    // MARK: - loadBase64/loadData 실패

    @Test("loadData - 파일 삭제 후 실패")
    func loadDataAfterDelete() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/png")
        att.delete()
        #expect(throws: (any Error).self) {
            _ = try att.loadData()
        }
    }

    @Test("loadBase64 - 파일 삭제 후 실패")
    func loadBase64AfterDelete() throws {
        let att = try FileAttachment.save(data: Data("test".utf8), mimeType: "image/png")
        att.delete()
        #expect(throws: (any Error).self) {
            _ = try att.loadBase64()
        }
    }

    // MARK: - 정확한 크기 경계

    @Test("save - 정확히 20MB는 성공")
    func saveExact20MB() throws {
        let data = Data(repeating: 0x00, count: 20 * 1024 * 1024)
        let att = try FileAttachment.save(data: data, mimeType: "image/png")
        att.delete()
        #expect(att.fileSizeBytes == 20 * 1024 * 1024)
    }

    // MARK: - mimeType 4바이트 경계

    @Test("mimeType - 정확히 4바이트")
    func mimeTypeExact4Bytes() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(FileAttachment.mimeType(for: data) == "image/png")
    }

    @Test("mimeType - 3바이트 JPEG 앞부분")
    func mimeType3BytesJPEG() {
        let data = Data([0xFF, 0xD8, 0xFF])
        #expect(FileAttachment.mimeType(for: data) == nil)
    }
}
