import SwiftUI
import UserNotifications

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = SessionMonitor()

    var body: some Scene {
        WindowGroup("ClaudeWatch") {
            DashboardView(monitor: monitor)
                .frame(minWidth: 400, minHeight: 300)
                .onAppear {
                    setupWindow()
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
        }
        .defaultSize(width: 440, height: 560)
    }

    private func setupWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let w = NSApplication.shared.windows.first(where: { $0.title.contains("ClaudeWatch") }) else { return }
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.title = "ClaudeWatch"
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Show notifications even when app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
