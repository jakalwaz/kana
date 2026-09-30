import AppKit
import UserNotifications

/// macOS notifications: a long command finished while you were elsewhere, or
/// a program asked for you (OSC 9 / OSC 777, which Claude Code sends when it
/// needs input). Clicking one brings its pane back. Permission is asked the
/// first time something is posted, not at launch.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// A notification was clicked: the `paneID` it was posted for.
    var onOpen: ((String) -> Void)?

    /// UNUserNotificationCenter needs a real app bundle; a bare `swift run`
    /// has none and would crash.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// Call once at launch, so clicks on notifications from earlier runs land.
    func start() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String, paneID: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["pane": paneID]
        content.threadIdentifier = paneID
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let pane = response.notification.request.content.userInfo["pane"] as? String else { return }
        await MainActor.run { onOpen?(pane) }
    }

    /// Kana only posts for panes you're not looking at, so show it even while
    /// Kana is in front (it may be another window or tab).
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
