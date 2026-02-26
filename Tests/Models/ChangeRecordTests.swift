import Testing
import Foundation
@testable import AgentManagerLib

@Suite("ChangeRecord Model Tests")
struct ChangeRecordTests {

    @Test("기본 초기화")
    func initDefaults() {
        let record = ChangeRecord(description: "test", commitHash: "abc123")
        #expect(record.description == "test")
        #expect(record.commitHash == "abc123")
        #expect(record.status == .applied)
        #expect(record.filesChanged.isEmpty)
        #expect(record.requestText == "")
    }

    @Test("모든 파라미터 초기화")
    func initAllParameters() {
        let date = Date()
        let record = ChangeRecord(
            date: date,
            description: "새 기능 추가",
            commitHash: "def456",
            status: .rolledBack,
            filesChanged: ["file1.swift", "file2.swift"],
            requestText: "버튼 추가해줘"
        )
        #expect(record.description == "새 기능 추가")
        #expect(record.commitHash == "def456")
        #expect(record.status == .rolledBack)
        #expect(record.filesChanged.count == 2)
        #expect(record.requestText == "버튼 추가해줘")
    }

    @Test("Identifiable - 고유 ID")
    func uniqueIDs() {
        let a = ChangeRecord(description: "a", commitHash: "aaa")
        let b = ChangeRecord(description: "b", commitHash: "bbb")
        #expect(a.id != b.id)
    }

    @Test("Codable 라운드트립")
    func codableRoundTrip() throws {
        let original = ChangeRecord(
            description: "버그 수정",
            commitHash: "789abc",
            status: .applied,
            filesChanged: ["Models/Agent.swift"],
            requestText: "버그 고쳐줘"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChangeRecord.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.description == original.description)
        #expect(decoded.commitHash == original.commitHash)
        #expect(decoded.status == original.status)
        #expect(decoded.filesChanged == original.filesChanged)
        #expect(decoded.requestText == original.requestText)
    }

    @Test("ChangeStatus enum rawValue")
    func changeStatusRawValues() {
        #expect(ChangeRecord.ChangeStatus.applied.rawValue == "applied")
        #expect(ChangeRecord.ChangeStatus.rolledBack.rawValue == "rolledBack")
        #expect(ChangeRecord.ChangeStatus.failed.rawValue == "failed")
    }

    @Test("ChangeStatus Codable")
    func changeStatusCodable() throws {
        var record = ChangeRecord(description: "test", commitHash: "abc", status: .applied)
        let data1 = try JSONEncoder().encode(record)
        let decoded1 = try JSONDecoder().decode(ChangeRecord.self, from: data1)
        #expect(decoded1.status == .applied)

        record.status = .rolledBack
        let data2 = try JSONEncoder().encode(record)
        let decoded2 = try JSONDecoder().decode(ChangeRecord.self, from: data2)
        #expect(decoded2.status == .rolledBack)
    }

    @Test("Codable - 배열 라운드트립")
    func codableArrayRoundTrip() throws {
        let records = [
            ChangeRecord(description: "feat1", commitHash: "aaa"),
            ChangeRecord(description: "feat2", commitHash: "bbb", status: .failed),
            ChangeRecord(description: "feat3", commitHash: "ccc", status: .rolledBack)
        ]
        let data = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([ChangeRecord].self, from: data)
        #expect(decoded.count == 3)
        #expect(decoded[0].status == .applied)
        #expect(decoded[1].status == .failed)
        #expect(decoded[2].status == .rolledBack)
    }

    @Test("status mutable")
    func statusMutable() {
        var record = ChangeRecord(description: "test", commitHash: "abc")
        #expect(record.status == .applied)
        record.status = .rolledBack
        #expect(record.status == .rolledBack)
        record.status = .failed
        #expect(record.status == .failed)
    }
}
