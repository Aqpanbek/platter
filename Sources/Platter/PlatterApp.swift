import AppKit

@main
enum PlatterMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render") {
            // Dev tool: write each scene to PNG with sample covers, then exit.
            PreviewRenderer.renderScenes(to: URL(fileURLWithPath: args.indices.contains(i + 1) ? args[i + 1] : "."))
            return
        }
        if let i = args.firstIndex(of: "--icon"), args.indices.contains(i + 1) {
            PreviewRenderer.renderIcon(to: URL(fileURLWithPath: args[i + 1]))
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private let player = NowPlayingService()
    private lazy var desktop = DesktopController(player: player, prefs: prefs)
    private lazy var status = StatusController(player: player, prefs: prefs)

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = status
        desktop.start()
        player.start()

        // First run: show the panel as a window so it's obvious where the controls live.
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            status.openWindow()
        }
    }

    /// Opening the app again (Finder, Spotlight, `open`) brings up the panel window —
    /// a way in even when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status.openWindow()
        return false
    }
}
