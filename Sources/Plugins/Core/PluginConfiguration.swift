import Foundation

/// 플러그인별 설정 저장소
/// 일반 값 → UserDefaults, 비밀 값 → KeychainHelper
enum PluginConfigStore {
    private static let enabledPrefix = "pluginEnabled_"
    private static let configPrefix = "pluginConfig_"

    // MARK: - 활성화 상태

    static func isEnabled(_ pluginID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledPrefix + pluginID)
    }

    static func setEnabled(_ pluginID: String, enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledPrefix + pluginID)
    }

    // MARK: - 설정 값 읽기/쓰기

    static func getValue(_ key: String, pluginID: String, isSecret: Bool = false, defaults: UserDefaults = .standard) -> String? {
        if isSecret {
            return try? KeychainHelper.load(key: configPrefix + pluginID + "_" + key)
        }
        return defaults.string(forKey: configPrefix + pluginID + "_" + key)
    }

    static func setValue(_ value: String?, key: String, pluginID: String, isSecret: Bool = false, defaults: UserDefaults = .standard) {
        if isSecret {
            if let value, !value.isEmpty {
                _ = try? KeychainHelper.save(key: configPrefix + pluginID + "_" + key, value: value)
            } else {
                _ = try? KeychainHelper.delete(key: configPrefix + pluginID + "_" + key)
            }
        } else {
            defaults.set(value, forKey: configPrefix + pluginID + "_" + key)
        }
    }
}
