import Foundation
import ServiceManagement

enum SceneKind: String, CaseIterable, Identifiable {
    case room, turntable, cassette, discman, boombox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: return "Room"
        case .turntable: return "Turntable"
        case .cassette: return "Cassette"
        case .discman: return "Discman"
        case .boombox: return "Boombox"
        }
    }

    var symbol: String {
        switch self {
        case .room: return "lamp.desk"
        case .turntable: return "record.circle"
        case .cassette: return "recordingtape"
        case .discman: return "opticaldisc"
        case .boombox: return "hifispeaker.fill"
        }
    }
}

/// The light a scene is painted in.
enum LightMood: String, CaseIterable {
    case day, sunset, night
}

/// The lighting setting: a fixed mood, or one that follows the clock.
enum Lighting: String, CaseIterable, Identifiable {
    case day, sunset, night, auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .sunset: return "Sunset"
        case .night: return "Night"
        case .auto: return "Auto"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "sun.max"
        case .sunset: return "sun.horizon"
        case .night: return "moon.stars"
        case .auto: return "clock"
        }
    }

    /// Auto: day 07–17, sunset 17–20, night otherwise.
    func mood(at date: Date = Date()) -> LightMood {
        switch self {
        case .day: return .day
        case .sunset: return .sunset
        case .night: return .night
        case .auto:
            let hour = Calendar.current.component(.hour, from: date)
            if (7..<17).contains(hour) { return .day }
            if (17..<20).contains(hour) { return .sunset }
            return .night
        }
    }
}

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private var syncingLoginItem = false

    @Published var scene: SceneKind {
        didSet { defaults.set(scene.rawValue, forKey: "scene") }
    }

    @Published var lighting: Lighting {
        didSet { defaults.set(lighting.rawValue, forKey: "lighting") }
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
        let followedClock = defaults.bool(forKey: "roomFollowsClock")
        // Earlier versions had day and night rooms as separate scenes, and a Gallery scene.
        switch stored {
        case "listeningRoom": scene = .room; lighting = followedClock ? .auto : .day
        case "afterHours": scene = .room; lighting = followedClock ? .auto : .night
        case "auto": scene = .room; lighting = .auto
        case "gallery": scene = .boombox; lighting = .auto
        default:
            scene = SceneKind(rawValue: stored) ?? .turntable
            lighting = Lighting(rawValue: defaults.string(forKey: "lighting") ?? "") ?? .auto
        }
        hideWhenPaused = defaults.bool(forKey: "hideWhenPaused")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        defaults.set(scene.rawValue, forKey: "scene")
        defaults.set(lighting.rawValue, forKey: "lighting")
        defaults.removeObject(forKey: "roomFollowsClock")
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
