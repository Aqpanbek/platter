import Foundation
import ServiceManagement

enum SceneKind: String, CaseIterable, Identifiable {
    case listeningRoom, afterHours, turntable, cassette, discman, boombox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listeningRoom: return "Listening Room"
        case .afterHours: return "After Hours"
        case .turntable: return "Turntable"
        case .cassette: return "Cassette"
        case .discman: return "Discman"
        case .boombox: return "Boombox"
        }
    }

    var symbol: String {
        switch self {
        case .listeningRoom: return "sun.max"
        case .afterHours: return "moon.stars"
        case .turntable: return "record.circle"
        case .cassette: return "recordingtape"
        case .discman: return "opticaldisc"
        case .boombox: return "hifispeaker.fill"
        }
    }

    var isRoom: Bool { self == .listeningRoom || self == .afterHours }
}

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private var syncingLoginItem = false

    @Published var scene: SceneKind {
        didSet { defaults.set(scene.rawValue, forKey: "scene") }
    }

    /// When a room scene is picked, show After Hours from 19:00 to 07:00 and Listening Room otherwise.
    @Published var roomFollowsClock: Bool {
        didSet { defaults.set(roomFollowsClock, forKey: "roomFollowsClock") }
    }

    @Published var hideWhenPaused: Bool {
        didSet { defaults.set(hideWhenPaused, forKey: "hideWhenPaused") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLoginItem, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    init() {
        let stored = defaults.string(forKey: "scene") ?? ""
        if stored == "auto" {
            // "Day & Night" used to be a scene of its own.
            scene = .listeningRoom
            roomFollowsClock = true
        } else {
            // Gallery was replaced by Boombox.
            scene = SceneKind(rawValue: stored == "gallery" ? "boombox" : stored) ?? .turntable
            roomFollowsClock = defaults.bool(forKey: "roomFollowsClock")
        }
        hideWhenPaused = defaults.bool(forKey: "hideWhenPaused")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The scene to show right now.
    func resolvedScene(at date: Date = Date()) -> SceneKind {
        guard roomFollowsClock, scene.isRoom else { return scene }
        let hour = Calendar.current.component(.hour, from: date)
        return (7..<19).contains(hour) ? .listeningRoom : .afterHours
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Platter: launch at login failed: \(error.localizedDescription)")
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin {
            DispatchQueue.main.async {
                self.syncingLoginItem = true
                self.launchAtLogin = actual
                self.syncingLoginItem = false
            }
        }
    }
}
