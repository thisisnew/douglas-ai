import Testing
import Foundation
@testable import DOUGLAS

@Suite("DocumentRequestDetector Tests")
struct DocumentRequestDetectorTests {

    // MARK: - 강한 문서 요청 감지

    @Test("quickDetect — '문서로 정리해줘' → 감지")
    func detectDocumentRequest() {
        let result = DocumentRequestDetector.quickDetect("문서로 정리해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
    }

    @Test("quickDetect — 'pdf로 저장해줘' → 감지")
    func detectPdfRequest() {
        let result = DocumentRequestDetector.quickDetect("pdf로 저장해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
    }

    @Test("quickDetect — '보고서로 뽑아줘' → report 타입 감지")
    func detectReportRequest() {
        let result = DocumentRequestDetector.quickDetect("보고서로 뽑아줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
        #expect(result?.suggestedDocType == .report)
    }

    @Test("quickDetect — '기획서로 작성해줘' → prd 타입 감지")
    func detectPrdRequest() {
        let result = DocumentRequestDetector.quickDetect("기획서로 작성해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
        #expect(result?.suggestedDocType == .prd)
    }

    @Test("quickDetect — '마크다운으로 정리해줘' → 감지")
    func detectMarkdownRequest() {
        let result = DocumentRequestDetector.quickDetect("마크다운으로 정리해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
    }

    @Test("quickDetect — '파일로 저장해줘' → 감지")
    func detectFileSaveRequest() {
        let result = DocumentRequestDetector.quickDetect("파일로 저장해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
    }

    @Test("quickDetect — '문서 작성해줘' → 감지")
    func detectDocWriteRequest() {
        let result = DocumentRequestDetector.quickDetect("문서 작성해줘")
        #expect(result != nil)
        #expect(result?.isDocumentRequest == true)
    }

    // MARK: - 비문서 요청 (감지 안 됨)

    @Test("quickDetect — '더 분석해줘' → 미감지")
    func noDetectAnalysis() {
        let result = DocumentRequestDetector.quickDetect("더 분석해줘")
        // nil이거나 isDocumentRequest == false
        #expect(result == nil || result?.isDocumentRequest == false)
    }

    @Test("quickDetect — '다른 관점에서 봐줘' → 미감지")
    func noDetectOtherPerspective() {
        let result = DocumentRequestDetector.quickDetect("다른 관점에서 봐줘")
        #expect(result == nil || result?.isDocumentRequest == false)
    }

    @Test("quickDetect — '이해가 안 돼' → 미감지")
    func noDetectClarification() {
        let result = DocumentRequestDetector.quickDetect("이해가 안 돼")
        #expect(result == nil || result?.isDocumentRequest == false)
    }
}
