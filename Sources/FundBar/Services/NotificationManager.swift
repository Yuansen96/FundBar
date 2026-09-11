import Foundation
import UserNotifications

/// 系统通知:涨跌提醒。授权在用户打开开关时才请求。
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// 前台时也显示横幅(需要在 app 启动时设置 delegate)
    final class PresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    private static let presentationDelegate = PresentationDelegate()

    /// app 启动时调用一次
    func installPresentationDelegate() {
        UNUserNotificationCenter.current().delegate = Self.presentationDelegate
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 用户拒绝时提醒静默失效,不做二次弹窗
        }
    }

    func sendFundAlert(_ candidate: FundAlertCandidate, date: String) {
        let content = UNMutableNotificationContent()
        content.title = "基金涨跌提醒"
        let direction = candidate.percent >= 0 ? "上涨" : "下跌"
        content.body = "\(candidate.name) 今日\(direction) \(candidate.percent.percentText),已越过提醒阈值"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: FundAlert.notifiedKey(code: candidate.code, date: date),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
