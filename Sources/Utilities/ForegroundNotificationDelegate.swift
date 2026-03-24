import Foundation
import UserNotifications

/// 포그라운드에서도 macOS 배너 알림을 표시하기 위한 delegate
/// macOS 기본 동작: 앱이 활성 상태면 배너 알림 안 뜸 → 이 delegate로 override
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
