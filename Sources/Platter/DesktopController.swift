import AppKit
import Combine

/// Owns one desktop-level window per screen and keeps their scenes in sync with the player.
final class DesktopController {
    private let player: NowPlayingService
    private let prefs: Preferences
    private var windows: [DesktopWindow] = []
    private var cancellables = Set<AnyCancellable>()
    private var clock: Timer?
    private var kind: SceneKind = .turntable
    private var track: Track?
    private var artwork: CGImage?
    private var history: [CGImage] = []

    init(player: NowPlayingService, prefs: Preferences) {
        self.player = player
        self.prefs = prefs
    }

    func start() {
        kind = prefs.resolvedScene()
        rebuildWindows()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.rebuildWindows()
        }

        player.$artwork.combineLatest(player.$history)
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] art, history in
                guard let self else { return }
                artwork = art?.cg
                self.history = history.compactMap(\.cg)
                windows.forEach { $0.scene.setArtwork(self.artwork, history: self.history, animated: true) }
            }
            .store(in: &cancellables)

        player.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] track in self?.trackDidChange(track) }
            .store(in: &cancellables)

        prefs.$scene.combineLatest(prefs.$roomFollowsClock)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshScene() }
            .store(in: &cancellables)

        prefs.$hideWhenPaused
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshScene()
        }
    }

    /// Switches scenes when the setting, or the clock for a day/night room, calls for another one.
    private func refreshScene() {
        let resolved = prefs.resolvedScene()
        guard resolved != kind else { return }
        kind = resolved
        windows.forEach { $0.transition(to: resolved) }
    }

    private func trackDidChange(_ track: Track?) {
        if let old = self.track, let new = track, old.id != new.id, old.progress(at: Date()) < 0.95 {
            // Jumped to another track rather than reaching the end of this one.
            let backwards = player.lastCommand.map { $0.command == .previous && Date().timeIntervalSince($0.at) < 3 } ?? false
            windows.forEach { $0.scene.trackSkipped(backwards: backwards) }
        }
        self.track = track
        let playing = track?.isPlaying ?? false
        let progress = track?.progress(at: Date()) ?? 0
        for w in windows {
            w.scene.setTrackInfo(title: track?.title ?? "", artist: track?.artist ?? "", animated: true)
            w.scene.setPlaying(playing, animated: true)
            w.scene.setProgress(progress, animated: true)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let show = track.map { $0.isPlaying || !prefs.hideWhenPaused } ?? false
        windows.forEach { $0.setShown(show) }
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let w = DesktopWindow(screen: screen, kind: kind)
            w.scene.setArtwork(artwork, history: history, animated: false)
            w.scene.setTrackInfo(title: track?.title ?? "", artist: track?.artist ?? "", animated: false)
            w.scene.setPlaying(track?.isPlaying ?? false, animated: false)
            w.scene.setProgress(track?.progress(at: Date()) ?? 0, animated: false)
            return w
        }
        updateVisibility()
    }
}

/// A borderless, click-through window that sits above the wallpaper and below the desktop icons.
final class DesktopWindow: NSWindow {
    private(set) var scene: DesktopScene
    private let host: NSView
    private var wantsShown = false

    init(screen: NSScreen, kind: SceneKind) {
        host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        scene = DesktopScene.make(kind)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        alphaValue = 0
        setFrame(screen.frame, display: false)

        // Layer-hosting: we own the layer tree, AppKit leaves it alone.
        host.layer = CALayer()
        host.wantsLayer = true
        host.layer?.backgroundColor = .black
        contentView = host
        install(scene)
    }

    private func install(_ scene: DesktopScene) {
        scene.layout(size: host.bounds.size, scale: backingScaleFactor)
        host.layer?.addSublayer(scene.root)
    }

    /// Cross-fades to a freshly built scene of another kind.
    func transition(to kind: SceneKind) {
        let old = scene
        let new = DesktopScene.make(kind)
        new.adoptState(from: old)
        install(new)
        scene = new
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.9
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        new.root.add(fade, forKey: "fadeIn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { old.root.removeFromSuperlayer() }
    }

    func setShown(_ shown: Bool) {
        guard shown != wantsShown else { return }
        wantsShown = shown
        if shown { orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            animator().alphaValue = shown ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, !wantsShown else { return }
            orderOut(nil)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
