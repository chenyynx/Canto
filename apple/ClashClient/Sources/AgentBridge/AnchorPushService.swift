import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

// AnchorPushService — P4 后台可达：APNs 注册 + 静默推送处理。
//
// 链路：
//   1. App 启动且已配对 → 请求通知权限（alert 授权非必须，静默推送只需要
//      registration；但 iOS 要求申请过授权才回调 token，申请 provisional 即可）
//      → didRegisterForRemoteNotificationsWithDeviceToken 拿到 hex token
//   2. token 存 AnchorPushTokenStore（App Group defaults），并在下一次
//      hello 时随消息上报 daemon（daemon 存 devices.apns_token）
//   3. daemon 设备离线时有命令 → Wake Gateway → APNs 静默推送
//      （content-available: 1, anchor: {dev, reason: "wake"}）
//   4. iOS 后台拉起 App（数十秒）→ AppDelegate.didReceiveRemoteNotification
//      → AnchorConnector 补连 daemon → 补发队列命令
//
// 注意：免签名侧载（无开发者账号推送能力）时注册会失败——安全降级：
// 无 token = 设备只能前台可达（P2 行为），其余功能不受影响。

/// APNs token 存储（App Group defaults，daemon hello 时上报用）。
enum AnchorPushTokenStore {
    static let tokenKey = "anchor.apns.token"
    static let envKey = "anchor.apns.env"
    static let topicKey = "anchor.apns.topic"

    static func save(token hex: String, env: String, topic: String?) {
        guard let defaults = UserDefaults(suiteName: ClashAppIdentifiers.appGroup) else { return }
        defaults.set(hex, forKey: tokenKey)
        defaults.set(env, forKey: envKey)
        if let topic { defaults.set(topic, forKey: topicKey) }
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: ClashAppIdentifiers.appGroup) else { return }
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: envKey)
        defaults.removeObject(forKey: topicKey)
    }

    /// hello 上报结构（nil = 无 token，不携带 apns 字段）。
    static func report() -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: ClashAppIdentifiers.appGroup),
              let token = defaults.string(forKey: tokenKey) else { return nil }
        var out: [String: Any] = [
            "token": token,
            "env": defaults.string(forKey: envKey) ?? "prod",
        ]
        if let topic = defaults.string(forKey: topicKey) { out["topic"] = topic }
        return out
    }
}

#if canImport(UIKit)
/// UIApplicationDelegate 挂钩：注册回调 + 静默推送唤醒处理。
final class AnchorPushService: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AnchorPushService()
    /// 唤醒回调：App 被 APNs 静默推送拉起时触发（主线程）。装配点注入。
    var onWake: (() -> Void)?
    private(set) var registered = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 启动后调用（配对成功后也再调一次——未配对时不注册）。
    func registerIfNeeded() {
        guard !registered else { return }
        // provisional：静默推送其实不需要用户授权，但 iOS 要求至少调用过
        // requestAuthorization 才下发 token；provisional 不打扰用户。
        UNUserNotificationCenter.current().requestAuthorization(options: [.provisional]) { [weak self] granted, _ in
            guard let self, granted != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func unregister() {
        UIApplication.shared.unregisterForRemoteNotifications()
        AnchorPushTokenStore.clear()
        registered = false
    }

    // MARK: - 注册回调

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // topic = 主 App bundle id（Clash 主 App 的 Info.plist CFBundleIdentifier）
        let topic = Bundle.main.bundleIdentifier ?? "org.example.clash"
        // env：模拟器/开发证书走 sandbox，正式签名走 prod——按编译配置判断
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "prod"
        #endif
        AnchorPushTokenStore.save(token: hex, env: env, topic: topic)
        registered = true
        ClashLogStore.shared.append("anchor push: registered token \(hex.prefix(16))… env=\(env)", stream: .app, level: .info)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 免签名侧载常见——安全降级：前台可达（P2 行为），功能不缺
        ClashLogStore.shared.append("anchor push: register failed (\(error.localizedDescription)) — falling back to foreground-only", stream: .app, level: .warning)
        AnchorPushTokenStore.clear()
    }

    // MARK: - 静默推送（唤醒）

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Anchor 唤醒推送的特征：aps.content-available == 1 且 anchor.dev 存在
        let aps = userInfo["aps"] as? [String: Any]
        let isSilent = (aps?["content-available"] as? Int) == 1
        let anchorPayload = userInfo["anchor"] as? [String: Any]
        if isSilent, anchorPayload?["dev"] != nil {
            ClashLogStore.shared.append("anchor push: wake received", stream: .app, level: .info)
            DispatchQueue.main.async { self.onWake?() }
            completionHandler(.newData)
            return
        }
        completionHandler(.noData)
    }

    // MARK: - 前台通知展示（provisional 授权下不弹横幅，静默处理即可）

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [] // Anchor 的推送全是静默型，前台无需展示
    }
}
#else
/// macOS：无 APNs 静默唤醒通道，保留与 iOS 相同的调用面。
final class AnchorPushService {
    static let shared = AnchorPushService()
    var onWake: (() -> Void)?
    private(set) var registered = false

    func registerIfNeeded() {}
    func unregister() {
        AnchorPushTokenStore.clear()
        registered = false
    }
}
#endif
