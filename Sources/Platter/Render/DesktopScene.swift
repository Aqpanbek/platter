import AppKit
import QuartzCore

/// A full-screen layer tree painted behind the desktop icons. Subclasses build their layers in
/// `build()` and react to artwork / playback changes through the `…DidChange` hooks.
class DesktopScene {
    /// How often progress is pushed to scenes; progress-driven motion animates over the same span.
    static let progressTick: CFTimeInterval = 5

    let root = CALayer()
    private(set) var canvas = Canvas(size: Canvas.design, scale: 2)
    private(set) var artwork: CGImage?
    private(set) var history: [CGImage] = []
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var title = ""
    private(set) var artist = ""
    private var isBuilt = false
    private(set) var isSuspended = false

    static func make(_ kind: SceneKind) -> DesktopScene {
        switch kind {
        case .listeningRoom: return RoomScene(night: false)
        case .afterHours: return RoomScene(night: true)
        case .turntable: return TurntableScene()
        case .cassette: return CassetteScene()
        case .discman: return DiscmanScene()
        case .boombox: return BoomboxScene()
        }
    }

    init() {
        root.backgroundColor = .black
        root.masksToBounds = true
        root.anchorPoint = .zero
    }

    func layout(size: CGSize, scale: CGFloat) {
        canvas = Canvas(size: size, scale: scale)
        withoutAnimation {
            root.bounds = CGRect(origin: .zero, size: size)
            root.position = .zero
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            build()
            artworkDidChange(animated: false)
            trackInfoDidChange(animated: false)
            playbackDidChange(animated: false)
            progressDidChange(animated: false)
        }
        isBuilt = true
    }

    func setTrackInfo(title: String, artist: String, animated: Bool) {
        guard title != self.title || artist != self.artist else { return }
        self.title = title
        self.artist = artist
        guard isBuilt else { return }
        trackInfoDidChange(animated: animated)
    }

    func setArtwork(_ art: CGImage?, history: [CGImage], animated: Bool) {
        artwork = art
        self.history = history
        guard isBuilt else { return }
        artworkDidChange(animated: animated)
    }

    func setPlaying(_ playing: Bool, animated: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        guard isBuilt else { return }
        playbackDidChange(animated: animated)
    }

    func setProgress(_ value: Double, animated: Bool) {
        progress = min(1, max(0, value))
        guard isBuilt else { return }
        progressDidChange(animated: animated)
    }

    /// Freezes every animation in the scene without losing its place: the whole layer tree runs on
    /// the root's clock, so stopping that clock stops the GPU work too.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            let t = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            root.timeOffset = t
        } else {
            let paused = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }

    /// Copies artwork and playback state from the scene this one replaces.
    func adoptState(from other: DesktopScene) {
        artwork = other.artwork
        history = other.history
        isPlaying = other.isPlaying
        progress = other.progress
        title = other.title
        artist = other.artist
    }

    // MARK: Subclass hooks

    func build() {}
    func artworkDidChange(animated: Bool) {}
    func trackInfoDidChange(animated: Bool) {}
    /// The user jumped to another track (not a track ending on its own).
    func trackSkipped(backwards: Bool) {}

    // MARK: Button presses

    /// A key pushed `depth` design units into the body (down on screen) and let go.
    func tap(_ layer: CALayer, depth: CGFloat) {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
        a.values = [0, -depth * canvas.k, -depth * canvas.k, 0]
        a.keyTimes = [0, 0.25, 0.55, 1]
        a.duration = 0.42
        a.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear),
                             CAMediaTimingFunction(name: .easeOut)]
        a.isAdditive = true
        layer.add(a, forKey: "tap")
    }

    /// A latching key, like a tape deck's Play: stays down until released.
    func latch(_ layer: CALayer, down: Bool, depth: CGFloat, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.transform = down ? CATransform3DMakeTranslation(0, -depth * canvas.k, 0) : CATransform3DIdentity
        CATransaction.commit()
    }

    /// A round button seen from above, squeezed and released.
    func squeeze(_ layer: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, 0.84, 0.84, 1]
        a.keyTimes = [0, 0.25, 0.55, 1]
        a.duration = 0.38
        layer.add(a, forKey: "squeeze")
    }
    func playbackDidChange(animated: Bool) {}
    func progressDidChange(animated: Bool) {}

    // MARK: Helpers

    func addImageLayer(_ image: CGImage?, frame designRect: CGRect, to parent: CALayer? = nil) -> CALayer {
        let l = CALayer()
        l.frame = canvas.rect(designRect)
        l.contents = image
        (parent ?? root).addSublayer(l)
        return l
    }

    /// Renders a piece of the scene covering `designRect`, drawing in design coordinates.
    func patch(_ designRect: CGRect, _ draw: (CGContext) -> Void) -> CGImage {
        Draw.image(size: designRect.size, ppu: canvas.unit) { ctx in
            ctx.translateBy(x: -designRect.minX, y: -designRect.minY)
            draw(ctx)
        }
    }

    /// Swaps layer contents, cross-fading when `animated`.
    func setContents(_ layer: CALayer, _ image: CGImage?, animated: Bool, duration: CFTimeInterval = 0.9) {
        if animated {
            let t = CATransition()
            t.type = .fade
            t.duration = duration
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(t, forKey: "contents")
        }
        layer.contents = image
    }

    func applyShadow(_ layer: CALayer, dx: CGFloat, dy: CGFloat, blur: CGFloat, opacity: Float, path: CGPath? = nil) {
        layer.shadowColor = .black
        layer.shadowOpacity = opacity
        layer.shadowRadius = blur * canvas.k
        layer.shadowOffset = CGSize(width: dx * canvas.k, height: -dy * canvas.k)
        layer.shadowPath = path ?? CGPath(rect: layer.bounds, transform: nil)
    }
}
