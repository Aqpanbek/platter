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

    /// The light the scene is painted in; fixed for the scene's lifetime (a new mood builds a new scene).
    let mood: LightMood

    static func make(_ kind: SceneKind, mood: LightMood) -> DesktopScene {
        switch kind {
        case .room: return RoomScene(mood: mood)
        case .turntable: return TurntableScene(mood: mood)
        case .cassette: return CassetteScene(mood: mood)
        case .discman: return DiscmanScene(mood: mood)
        case .boombox: return BoomboxScene(mood: mood)
        }
    }

    init(mood: LightMood) {
        self.mood = mood
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

    // MARK: Lighting

    /// A light source that holds back the dark at night.
    struct Lamp {
        var center: CGPoint
        var radius: CGFloat
        var strength: Double = 0.78
    }

    /// Something that emits its own light (a display, meters): kept bright above the night grade,
    /// with a coloured halo around `halo`.
    struct Glow {
        var layer: CALayer
        var halo: CGRect? = nil
        var color: UInt32 = 0xFFFFFF
    }

    /// Grades everything built so far for the time of day. Call at the end of `build()`.
    func applyMood(lamps: [Lamp], glowing: [Glow] = []) {
        let full = CGRect(origin: .zero, size: Canvas.design)
        switch mood {
        case .day:
            return
        case .sunset:
            _ = addImageLayer(sunsetGrade(), frame: full)
        case .night:
            _ = addImageLayer(nightShade(lamps), frame: full)
            _ = addImageLayer(lampGlow(lamps), frame: full)
            for glow in glowing {
                defer {
                    glow.layer.removeFromSuperlayer()
                    root.addSublayer(glow.layer)
                }
                guard let source = glow.halo else { continue }
                // Wide sources (a tuning dial) get a halo that hugs them instead of spilling sideways.
                let halo = source.insetBy(dx: -min(source.width * 0.6, 110), dy: -max(source.height * 0.9, 28))
                _ = addImageLayer(patch(halo) { ctx in
                    ctx.saveGState()
                    ctx.translateBy(x: halo.midX, y: halo.midY)
                    ctx.scaleBy(x: 1, y: halo.height / halo.width)
                    ctx.drawRadialGradient(makeGradient([(0, rgb(glow.color, 0.34)), (0.45, rgb(glow.color, 0.12)), (1, rgb(glow.color, 0))]),
                                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: halo.width / 2, options: [])
                    ctx.restoreGState()
                }, frame: halo)
            }
        }
    }

    /// Low golden sun: warm from the top left, cooling to dusk at the bottom right, with long beams.
    private func sunsetGrade() -> CGImage {
        let img = Draw.image(size: Canvas.design, ppu: 0.25) { ctx in
            ctx.drawLinearGradient(makeGradient([(0, rgb(0xFF9248, 0.24)), (0.5, rgb(0xFF6A5A, 0.12)), (1, rgb(0x4A2048, 0.34))]),
                                   start: .zero, end: CGPoint(x: 1600, y: 1040), options: [])
            for x0 in [-200.0, 260.0, 820.0] as [CGFloat] {
                ctx.fill(.polygon([CGPoint(x: x0, y: -40), CGPoint(x: x0 + 170, y: -40),
                                   CGPoint(x: x0 + 900, y: 1080), CGPoint(x: x0 + 620, y: 1080)]), rgb(0xFFD08A, 0.09))
            }
        }
        return Draw.blur(img, sigma: 5)
    }

    /// Cool darkness everywhere except where the lamps reach.
    private func nightShade(_ lamps: [Lamp]) -> CGImage {
        lightField(lamps) { light in
            // Even under the lamp it stays a little dim; away from it the room falls into deep blue.
            let a = min(0.88, max(0.2, 0.88 - light * 0.85))
            return (SIMD3(8, 10, 22), a)
        }
    }

    /// Warm tint of lamplight on whatever it falls on.
    private func lampGlow(_ lamps: [Lamp]) -> CGImage {
        lightField(lamps) { light in (SIMD3(255, 176, 104), min(0.3, light * 0.22)) }
    }

    private func lightField(_ lamps: [Lamp], _ shade: (Double) -> (SIMD3<Double>, Double)) -> CGImage {
        let w = 400, h = 260
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let px = (Double(x) + 0.5) / Double(w) * 1600, py = (Double(y) + 0.5) / Double(h) * 1040
                var light = 0.0
                for lamp in lamps {
                    let d = hypot(px - Double(lamp.center.x), py - Double(lamp.center.y))
                    light += lamp.strength * exp(-pow(d / Double(lamp.radius), 2))
                }
                let (color, a) = shade(light)
                let i = (y * w + x) * 4
                buf[i] = UInt8(color.x * a)
                buf[i + 1] = UInt8(color.y * a)
                buf[i + 2] = UInt8(color.z * a)
                buf[i + 3] = UInt8(255 * a)
            }
        }
        return Texture.makeImage(buf, width: w, height: h)
    }

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
