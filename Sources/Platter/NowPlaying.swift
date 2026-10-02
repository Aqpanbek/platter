import AppKit
import Combine

enum PlayerSource: String {
    case spotify, music

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool
    var source: PlayerSource
    var artworkURL: URL?
    var sampledAt: Date

    /// Identifies the cover, so switching tracks within an album doesn't reload it.
    var artworkKey: String {
        artworkURL?.absoluteString ?? "\(source.rawValue)|\(artist)|\(album)"
    }

    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(sampledAt))
    }

    func progress(at date: Date) -> Double {
        duration > 0 ? position(at: date) / duration : 0
    }
}

enum PlayerCommand {
    case playPause, next, previous

    var verb: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }
}

/// Watches Spotify and Apple Music over AppleScript and publishes what's playing and its cover.
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// Covers of previously played albums, newest first.
    @Published private(set) var history: [NSImage] = []
    /// A player that is running but hasn't granted Automation access.
    @Published private(set) var blockedSource: PlayerSource?
    /// The last transport command sent from Platter, so scenes can press the matching button.
    private(set) var lastCommand: (command: PlayerCommand, at: Date)?

    private let scripts = ScriptRunner()
    private var timer: Timer?
    private var lastActive: PlayerSource?
    private var requestedKey: String?
    private var shownKey: String?
    private var historyKeys: [String] = []
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            center.addObserver(self, selector: #selector(playerDidChange), name: .init(name), object: nil)
        }
        // The players announce track and play/pause changes themselves; this slow poll only corrects drift
        // in the position, which is otherwise extrapolated from the last sample.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 3
        refresh()
    }

    func send(_ command: PlayerCommand) {
        guard let source = track?.source ?? lastActive else { return }
        lastCommand = (command, Date())
        _ = scripts.run("tell application id \"\(source.bundleID)\" to \(command.verb)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    @objc private func playerDidChange(_ note: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
    }

    func refresh() {
        var found: [Track] = []
        var blocked: PlayerSource?
        for source in [PlayerSource.spotify, .music] where source.isRunning {
            switch query(source) {
            case .success(let t?): found.append(t)
            case .success(nil): break
            case .failure(.notAuthorized): blocked = source
            case .failure: break
            }
        }
        if blockedSource != blocked { blockedSource = blocked }

        let next = found.first(where: \.isPlaying)
            ?? found.first(where: { $0.source == lastActive })
            ?? found.first
        if let next, next.isPlaying { lastActive = next.source }
        if track != next { track = next }

        if let next, next.artworkKey != requestedKey {
            requestedKey = next.artworkKey
            loadArtwork(for: next)
        }
    }

    // MARK: - Player queries

    private func query(_ source: PlayerSource) -> Result<Track?, ScriptError> {
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application id "com.spotify.client"
                set ps to player state as string
                if ps is "stopped" then return {ps}
                set t to current track
                return {ps, id of t, name of t, artist of t, album of t, artwork url of t, (duration of t) / 1000, player position}
            end tell
            """
        case .music:
            script = """
            tell application id "com.apple.Music"
                set ps to player state as string
                if ps is "stopped" then return {ps}
                set t to current track
                return {ps, persistent ID of t, name of t, artist of t, album of t, "", duration of t, player position}
            end tell
            """
        }
        return scripts.run(script).map { d in
            guard d.numberOfItems >= 8, let state = d.atIndex(1)?.stringValue, state != "stopped" else { return nil }
            var art = d.atIndex(6)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            if art?.hasPrefix("http://") == true { art = "https://" + art!.dropFirst(7) }
            return Track(
                id: d.atIndex(2)?.stringValue ?? "",
                title: d.atIndex(3)?.stringValue ?? "",
                artist: d.atIndex(4)?.stringValue ?? "",
                album: d.atIndex(5)?.stringValue ?? "",
                duration: d.atIndex(7)?.doubleValue ?? 0,
                position: d.atIndex(8)?.doubleValue ?? 0,
                isPlaying: state == "playing",
                source: source,
                artworkURL: art.flatMap(URL.init(string:)),
                sampledAt: Date()
            )
        }
    }

    // MARK: - Artwork

    private func loadArtwork(for track: Track) {
        let key = track.artworkKey
        if let cached = cache[key] {
            show(cached, key: key)
            return
        }
        switch track.source {
        case .spotify:
            if let url = track.artworkURL {
                download(url) { [weak self] image in
                    if let image { self?.show(image, key: key) } else { self?.searchITunes(track, key: key) }
                }
            } else {
                searchITunes(track, key: key)
            }
        case .music:
            let script = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
                try
                    return data of artwork 1 of current track
                end try
                return ""
            end tell
            """
            if case .success(let d) = scripts.run(script), let image = NSImage(data: d.data), image.isValid {
                show(image, key: key)
            } else {
                searchITunes(track, key: key)
            }
        }
    }

    /// Fallback: look the album up in the iTunes catalogue.
    private func searchITunes(_ track: Track, key: String) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.album)"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = c.url else { return show(nil, key: key) }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            struct Response: Decodable {
                struct Item: Decodable { let artworkUrl100: String? }
                let results: [Item]
            }
            let small = data.flatMap { try? JSONDecoder().decode(Response.self, from: $0) }?.results.first?.artworkUrl100
            guard let large = small?.replacingOccurrences(of: "100x100bb", with: "1000x1000bb"),
                  let artURL = URL(string: large) else {
                DispatchQueue.main.async { self?.show(nil, key: key) }
                return
            }
            self?.download(artURL) { image in self?.show(image, key: key) }
        }.resume()
    }

    private func download(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    private func show(_ image: NSImage?, key: String) {
        guard key == requestedKey else { return }  // a newer track won the race
        if let image {
            cache[key] = image
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            if cacheOrder.count > 12 { cache[cacheOrder.removeFirst()] = nil }
        }
        if let old = artwork, let oldKey = shownKey, oldKey != key {
            var entries = zip(historyKeys, history).filter { $0.0 != oldKey && $0.0 != key }
            entries.insert((oldKey, old), at: 0)
            entries = Array(entries.prefix(4))
            historyKeys = entries.map(\.0)
            history = entries.map(\.1)
        }
        shownKey = key
        artwork = image
    }
}

enum ScriptError: Error {
    case notAuthorized
    case notRunning
    case failed(Int, String)
}

/// Compiles each AppleScript once and reuses it.
final class ScriptRunner {
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script = compiled[source] ?? {
            let s = NSAppleScript(source: source)!
            compiled[source] = s
            return s
        }()
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -1743: return .failure(.notAuthorized)
            case -600: return .failure(.notRunning)
            default: return .failure(.failed(code, error[NSAppleScript.errorMessage] as? String ?? ""))
            }
        }
        return .success(result)
    }
}
