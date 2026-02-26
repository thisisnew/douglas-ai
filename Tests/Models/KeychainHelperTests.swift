import Testing
import Foundation
@testable import AgentManagerLib

@Suite("KeychainHelper Tests")
struct KeychainHelperTests {

    /// 각 테스트에서 사용할 고유 키 (충돌 방지)
    private func uniqueKey() -> String {
        "test-key-\(UUID().uuidString)"
    }

    // MARK: - save / load 기본

    @Test("save + load - 값 저장 후 로드")
    func saveAndLoad() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "hello-world")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "hello-world")
        // cleanup
        try KeychainHelper.delete(key: key)
    }

    @Test("save - 같은 키 덮어쓰기")
    func saveOverwrite() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "first")
        try KeychainHelper.save(key: key, value: "second")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "second")
        try KeychainHelper.delete(key: key)
    }

    @Test("save - 한글 값")
    func saveKorean() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "안녕하세요 테스트")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "안녕하세요 테스트")
        try KeychainHelper.delete(key: key)
    }

    @Test("save - 특수 문자 포함")
    func saveSpecialChars() throws {
        let key = uniqueKey()
        let value = "sk-ant-api03-test!@#$%^&*()"
        try KeychainHelper.save(key: key, value: value)
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == value)
        try KeychainHelper.delete(key: key)
    }

    @Test("save - 빈 문자열")
    func saveEmptyString() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "")
        try KeychainHelper.delete(key: key)
    }

    @Test("save - 긴 문자열 (1000자)")
    func saveLongString() throws {
        let key = uniqueKey()
        let value = String(repeating: "a", count: 1000)
        try KeychainHelper.save(key: key, value: value)
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == value)
        try KeychainHelper.delete(key: key)
    }

    // MARK: - load 실패

    @Test("load - 존재하지 않는 키")
    func loadNonExistent() throws {
        let loaded = try KeychainHelper.load(key: "definitely-does-not-exist-\(UUID().uuidString)")
        #expect(loaded == nil)
    }

    // MARK: - delete

    @Test("delete - 존재하는 키")
    func deleteExisting() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "to-delete")
        let deleted = try KeychainHelper.delete(key: key)
        #expect(deleted == true)
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == nil)
    }

    @Test("delete - 존재하지 않는 키")
    func deleteNonExisting() throws {
        let deleted = try KeychainHelper.delete(key: "nonexistent-\(UUID().uuidString)")
        #expect(deleted == false)
    }

    @Test("delete - 이중 삭제")
    func deleteDouble() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "test")
        try KeychainHelper.delete(key: key)
        let secondDelete = try KeychainHelper.delete(key: key)
        #expect(secondDelete == false)
    }

    // MARK: - 키 이름 안전성

    @Test("save/load - 특수 문자 포함 키 이름")
    func specialKeyName() throws {
        let key = "test/key:with!special@chars#\(UUID().uuidString)"
        try KeychainHelper.save(key: key, value: "special-key-value")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "special-key-value")
        try KeychainHelper.delete(key: key)
    }

    // MARK: - KeychainError

    @Test("KeychainError.saveFailed - 에러 설명")
    func keychainErrorSave() {
        let error = KeychainError.saveFailed(0)
        #expect(error.localizedDescription.contains("저장"))
    }

    @Test("KeychainError.loadFailed - 에러 설명")
    func keychainErrorLoad() {
        let error = KeychainError.loadFailed(0)
        #expect(error.localizedDescription.contains("로드"))
    }

    @Test("KeychainError.deleteFailed - 에러 설명")
    func keychainErrorDelete() {
        let error = KeychainError.deleteFailed(0)
        #expect(error.localizedDescription.contains("삭제"))
    }

    @Test("KeychainError.dataConversionFailed - 에러 설명")
    func keychainErrorConversion() {
        let error = KeychainError.dataConversionFailed
        #expect(error.localizedDescription.contains("변환"))
    }
}
