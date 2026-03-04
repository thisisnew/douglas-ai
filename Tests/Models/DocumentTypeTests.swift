import Testing
import Foundation
@testable import DOUGLAS

@Suite("DocumentType Tests")
struct DocumentTypeTests {

    @Test("전체 케이스 6종 존재")
    func allCases() {
        let all = DocumentType.allCases
        #expect(all.count == 6)
        #expect(all.contains(.prd))
        #expect(all.contains(.technicalDesign))
        #expect(all.contains(.apiDoc))
        #expect(all.contains(.testPlan))
        #expect(all.contains(.report))
        #expect(all.contains(.freeform))
    }

    @Test("displayName 비어있지 않음")
    func displayNames() {
        for docType in DocumentType.allCases {
            #expect(!docType.displayName.isEmpty)
        }
    }

    @Test("iconName 비어있지 않음")
    func iconNames() {
        for docType in DocumentType.allCases {
            #expect(!docType.iconName.isEmpty)
        }
    }

    @Test("subtitle 비어있지 않음")
    func subtitles() {
        for docType in DocumentType.allCases {
            #expect(!docType.subtitle.isEmpty)
        }
    }

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        for docType in DocumentType.allCases {
            let data = try JSONEncoder().encode(docType)
            let decoded = try JSONDecoder().decode(DocumentType.self, from: data)
            #expect(decoded == docType)
        }
    }

    @Test("freeform은 빈 templateSections")
    func freeformEmptyTemplate() {
        #expect(DocumentType.freeform.templateSections.isEmpty)
        #expect(DocumentType.freeform.templatePromptBlock().isEmpty)
    }

    @Test("다른 유형은 비어있지 않은 templateSections")
    func nonFreeformHasTemplate() {
        for docType in DocumentType.allCases where docType != .freeform {
            #expect(!docType.templateSections.isEmpty)
            #expect(!docType.templatePromptBlock().isEmpty)
        }
    }

    @Test("templatePromptBlock에 displayName 포함")
    func templateBlockContainsName() {
        for docType in DocumentType.allCases where docType != .freeform {
            #expect(docType.templatePromptBlock().contains(docType.displayName))
        }
    }
}
