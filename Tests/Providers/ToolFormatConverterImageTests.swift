import Testing
import Foundation
@testable import DOUGLAS

@Suite("ToolFormatConverter Image Tests")
struct ToolFormatConverterImageTests {

    private func makeTempAttachment(mimeType: String = "image/png") throws -> ImageAttachment {
        let data = Data("fake image data".utf8)
        return try ImageAttachment.save(data: data, mimeType: mimeType)
    }

    // MARK: - Anthropic 이미지 블록

    @Test("anthropicContentBlocks - 텍스트 + 이미지")
    func anthropicWithTextAndImage() throws {
        let att = try makeTempAttachment()
        defer { att.delete() }

        let blocks = ToolFormatConverter.anthropicContentBlocks(text: "describe this", attachments: [att])
        #expect(blocks.count == 2) // image + text
        #expect(blocks[0]["type"] as? String == "image")
        #expect(blocks[1]["type"] as? String == "text")
        #expect(blocks[1]["text"] as? String == "describe this")

        let source = blocks[0]["source"] as? [String: Any]
        #expect(source?["type"] as? String == "base64")
        #expect(source?["media_type"] as? String == "image/png")
        #expect(source?["data"] != nil)
    }

    @Test("anthropicContentBlocks - 이미지만 (텍스트 nil)")
    func anthropicImageOnly() throws {
        let att = try makeTempAttachment()
        defer { att.delete() }

        let blocks = ToolFormatConverter.anthropicContentBlocks(text: nil, attachments: [att])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "image")
    }

    @Test("anthropicContentBlocks - 텍스트만 (빈 첨부)")
    func anthropicTextOnly() {
        let blocks = ToolFormatConverter.anthropicContentBlocks(text: "hello", attachments: [])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "text")
    }

    // MARK: - OpenAI 이미지 블록

    @Test("openAIContentArray - 텍스트 + 이미지")
    func openAIWithTextAndImage() throws {
        let att = try makeTempAttachment(mimeType: "image/jpeg")
        defer { att.delete() }

        let parts = ToolFormatConverter.openAIContentArray(text: "what is this?", attachments: [att])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "image_url")
        #expect(parts[1]["type"] as? String == "text")

        let imageURL = (parts[0]["image_url"] as? [String: Any])?["url"] as? String
        #expect(imageURL?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test("openAIContentArray - 이미지만")
    func openAIImageOnly() throws {
        let att = try makeTempAttachment()
        defer { att.delete() }

        let parts = ToolFormatConverter.openAIContentArray(text: nil, attachments: [att])
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image_url")
    }

    // MARK: - Google 이미지 블록

    @Test("googleParts - 텍스트 + 이미지")
    func googleWithTextAndImage() throws {
        let att = try makeTempAttachment(mimeType: "image/gif")
        defer { att.delete() }

        let parts = ToolFormatConverter.googleParts(text: "describe", attachments: [att])
        #expect(parts.count == 2)

        let inlineData = parts[0]["inlineData"] as? [String: Any]
        #expect(inlineData?["mimeType"] as? String == "image/gif")
        #expect(inlineData?["data"] != nil)
        #expect(parts[1]["text"] as? String == "describe")
    }

    @Test("googleParts - 이미지만")
    func googleImageOnly() throws {
        let att = try makeTempAttachment()
        defer { att.delete() }

        let parts = ToolFormatConverter.googleParts(text: nil, attachments: [att])
        #expect(parts.count == 1)
        #expect(parts[0]["inlineData"] != nil)
    }

    // MARK: - 다중 이미지

    @Test("다중 이미지 - Anthropic")
    func anthropicMultipleImages() throws {
        let att1 = try makeTempAttachment(mimeType: "image/png")
        let att2 = try makeTempAttachment(mimeType: "image/jpeg")
        defer { att1.delete(); att2.delete() }

        let blocks = ToolFormatConverter.anthropicContentBlocks(text: "compare", attachments: [att1, att2])
        #expect(blocks.count == 3) // 2 images + 1 text
    }
}
