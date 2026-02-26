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

    // MARK: - 암호화 테스트

    @Test("암호화 라운드트립 — 저장된 파일은 평문이 아님")
    func encryptionNotPlaintext() throws {
        let key = uniqueKey()
        let secret = "super-secret-api-key-12345"
        try KeychainHelper.save(key: key, value: secret)

        // 파일을 직접 읽어서 평문이 아닌지 확인
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let keysDir = appSupport.appendingPathComponent("AgentManager/keys", isDirectory: true)
        let safeName = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let fileURL = keysDir.appendingPathComponent("\(safeName).key")

        let rawData = try Data(contentsOf: fileURL)
        let rawString = String(data: rawData, encoding: .utf8)

        // 원본 평문이 파일에 그대로 들어있으면 안됨
        #expect(rawString != secret)
        // Base64로 디코딩해도 원문이 나오면 안됨 (암호화가 적용되었으므로)
        if let b64decoded = Data(base64Encoded: rawData),
           let b64string = String(data: b64decoded, encoding: .utf8) {
            #expect(b64string != secret)
        }

        // 하지만 KeychainHelper.load로는 정상 복호화
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == secret)

        try KeychainHelper.delete(key: key)
    }

    @Test("암호화 — 여러 키 독립적으로 저장/로드")
    func encryptionMultipleKeys() throws {
        let key1 = uniqueKey()
        let key2 = uniqueKey()
        try KeychainHelper.save(key: key1, value: "value-one")
        try KeychainHelper.save(key: key2, value: "value-two")

        #expect(try KeychainHelper.load(key: key1) == "value-one")
        #expect(try KeychainHelper.load(key: key2) == "value-two")

        try KeychainHelper.delete(key: key1)
        try KeychainHelper.delete(key: key2)
    }

    @Test("암호화 — 덮어쓰기 후에도 복호화 정상")
    func encryptionOverwrite() throws {
        let key = uniqueKey()
        try KeychainHelper.save(key: key, value: "original")
        try KeychainHelper.save(key: key, value: "updated")
        let loaded = try KeychainHelper.load(key: key)
        #expect(loaded == "updated")
        try KeychainHelper.delete(key: key)
    }
}
