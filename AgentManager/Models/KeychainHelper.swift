import Foundation
import Security
import CryptoKit
import os.log

// MARK: - Keychain 에러 (호환용)

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:        return "저장 실패"
        case .loadFailed:        return "로드 실패"
        case .deleteFailed:      return "삭제 실패"
        case .dataConversionFailed: return "데이터 변환 실패"
        }
    }
}

// MARK: - 파일 기반 키 저장소 (Keychain 대체)
// Keychain은 코드 서명 없는 앱에서 매번 승인 다이얼로그를 띄우므로,
// Application Support 내 파일로 대체. ChaChaPoly 암호화 적용.

enum KeychainHelper {
    private static let logger = Logger(subsystem: "com.agentmanager.app", category: "KeyStore")

    private static var keysDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // 극히 드문 실패 상황 — 폴백 경로
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dir = home.appendingPathComponent(".agentmanager/keys", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let dir = appSupport.appendingPathComponent("AgentManager/keys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for key: String) -> URL {
        // 키를 파일명으로 안전하게 변환
        let safeName = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return keysDirectory.appendingPathComponent("\(safeName).key")
    }

    // MARK: - 암호화 키 관리

    /// 디바이스별 고유 대칭키 파일 경로
    private static var encryptionKeyURL: URL {
        keysDirectory.appendingPathComponent(".encryption_key")
    }

    /// 대칭키 로드 또는 생성
    private static func getEncryptionKey() -> SymmetricKey {
        let url = encryptionKeyURL
        if let keyData = try? Data(contentsOf: url), keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }
        // 새 키 생성 후 저장
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try? keyData.write(to: url)
        // 파일 권한 제한 (소유자만 읽기/쓰기)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return newKey
    }

    // MARK: - 공개 API

    @discardableResult
    static func save(key: String, value: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        do {
            let symmetricKey = getEncryptionKey()
            let sealedBox = try ChaChaPoly.seal(data, using: symmetricKey)
            let combined = sealedBox.combined
            try combined.write(to: fileURL(for: key))
            return true
        } catch let error as KeychainError {
            throw error
        } catch {
            logger.error("Key save failed for '\(key)': \(error.localizedDescription)")
            throw KeychainError.saveFailed(0)
        }
    }

    static func load(key: String) throws -> String? {
        let url = fileURL(for: key)

        // 암호화된 파일에서 로드 시도
        if let fileData = try? Data(contentsOf: url) {
            // 먼저 ChaChaPoly 복호화 시도
            if let sealedBox = try? ChaChaPoly.SealedBox(combined: fileData) {
                let symmetricKey = getEncryptionKey()
                if let decrypted = try? ChaChaPoly.open(sealedBox, using: symmetricKey),
                   let value = String(data: decrypted, encoding: .utf8) {
                    return value
                }
            }

            // 기존 Base64 형식 마이그레이션 (하위 호환)
            if let decoded = Data(base64Encoded: fileData),
               let value = String(data: decoded, encoding: .utf8) {
                logger.info("Migrating Base64 key '\(key)' to encrypted format")
                _ = try? save(key: key, value: value)
                return value
            }
        }

        // 파일 없으면 레거시 Keychain에서 마이그레이션 시도
        if let legacyValue = loadFromLegacyKeychain(key: key) {
            _ = try? save(key: key, value: legacyValue)
            deleteLegacyKeychain(key: key)
            logger.info("Migrated key '\(key)' from Keychain to encrypted file")
            return legacyValue
        }

        return nil
    }

    @discardableResult
    static func delete(key: String) throws -> Bool {
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return true
        }
        return false
    }

    // MARK: - 레거시 Keychain 마이그레이션

    private static let legacyService = "com.agentmanager.app"

    private static func loadFromLegacyKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func deleteLegacyKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
