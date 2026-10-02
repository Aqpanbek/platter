import AppKit
import QuartzCore

/// Front view: a boombox on the floor against a sunlit wall. The cassette wears the cover, the
/// speakers thump, the EQ dances, the tuning needle tracks the song, and the top keys really press.
final class BoomboxScene: DesktopScene {
    private enum G {
        static let floorY: CGFloat = 800
        static let body = CGRect(x: 470, y: 340, width: 900, height: 450)
        static let panel = body.insetBy(dx: 20, dy: 20)
        static let speakers = [CGPoint(x: 655, y: 620), CGPoint(x: 1185, y: 620)]
        static let speakerRing: CGFloat = 144
        static let surround: CGFloat = 136
        static let cone: CGFloat = 118
        static let tweeters = [CGPoint(x: 655, y: 438), CGPoint(x: 1185, y: 438)]
        static let dial = CGRect(x: 520, y: 374, width: 800, height: 32)
        /// Inset of the frequency scale inside the dial, leaving room for the FM / MHz labels.
        static let dialPad: CGFloat = 50
        static let eq = CGRect(x: 812, y: 420, width: 216, height: 40)
        static let door = CGRect(x: 812, y: 472, width: 216, height: 150)
        static let shell = CGRect(x: 826, y: 484, width: 188, height: 124)
        static let label = CGRect(x: 834, y: 492, width: 172, height: 72)
        static let tapeWindow = CGRect(x: 858, y: 514, width: 124, height: 32)
        static let hubs = [CGPoint(x: 880, y: 530), CGPoint(x: 960, y: 530)]
        static let hubRadius: CGFloat = 10
        static let packRange: ClosedRange<CGFloat> = 11...26
        static let knobs: [(center: CGPoint, label: String)] = [(CGPoint(x: 860, y: 668), "VOLUME"), (CGPoint(x: 980, y: 668), "TONE")]
        /// Piano keys on top: record, play, rewind, fast-forward, stop, pause.
        static func key(_ i: Int) -> CGRect { CGRect(x: 742 + CGFloat(i) * 62, y: 306, width: 54, height: 44) }
        static let keyGlyphs = ["●", "▶", "◀◀", "▶▶", "■", "❚❚"]
        static let play = 1, rewind = 2, forward = 3, pause = 5
        static let keyTravel: CGFloat = 14
        static let eqBars = 12
        static let sleeve = CGRect(x: 112, y: 488, width: 300, height: 300)
        static let backCover = CGRect(x: 66, y: 500, width: 290, height: 290)
    }

    private let label = CALayer()
    private let sleeve = CALayer()
    private let backCover = CALayer()
    private let needle = CALayer()
    private var keys: [CALayer] = []
    private var cones: [CALayer] = []
    private var meters: [CALayer] = []
    private var bars: [CALayer] = []
    private var packs: [CALayer] = []
    private var spinners: [Spinner] = []

    override func build() {
        keys.removeAll()
        cones.removeAll()
        meters.removeAll()
        bars.removeAll()
        let full = CGRect(origin: .zero, size: Canvas.design)
        let k = canvas.k
        _ = addImageLayer(background(), frame: full)

        for (layer, rect, angle) in [(backCover, G.backCover, CGFloat(0.05)), (sleeve, G.sleeve, CGFloat(-0.035))] {
            layer.bounds = CGRect(x: 0, y: 0, width: rect.width * k, height: rect.height * k)
            layer.position = canvas.point(rect.center)
            layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            applyShadow(layer, dx: 24, dy: 4, blur: 20, opacity: 0.35)
            root.addSublayer(layer)
        }

        for i in G.keyGlyphs.indices {
            keys.append(addImageLayer(keyImage(i), frame: G.key(i)))
        }
        let bodyRect = G.body.insetBy(dx: -4, dy: -4)
        _ = addImageLayer(patch(bodyRect) { drawBody($0) }, frame: bodyRect)

        let coneImage = coneArt()
        for c in G.speakers {
            cones.append(addImageLayer(coneImage, frame: CGRect(center: c, radius: G.cone)))
        }

        let reels = Tape.reels(in: G.tapeWindow, hubs: G.hubs, hubRadius: G.hubRadius, canvas: canvas)
        root.addSublayer(reels.container)
        packs = reels.packs
        spinners = reels.hubs.map { Spinner(layer: $0, period: 3.4, clockwise: false) }
        label.frame = canvas.rect(G.label)
        root.addSublayer(label)
        _ = addImageLayer(patch(G.door) { drawDoorGlass($0) }, frame: G.door)

        // EQ bars grow from the bottom of the display.
        let barImage = eqBarArt()
        let inner = G.eq.insetBy(dx: 8, dy: 6)
        let step = inner.width / CGFloat(G.eqBars)
        for i in 0..<G.eqBars {
            let bar = CALayer()
            bar.contents = barImage
            bar.bounds = CGRect(x: 0, y: 0, width: (step - 4) * k, height: inner.height * k)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.position = canvas.point(CGPoint(x: inner.minX + step * (CGFloat(i) + 0.5), y: inner.maxY))
            // A mask that grows from the bottom reveals the LED segments rather than squashing them.
            let meter = CALayer()
            meter.backgroundColor = .black
            meter.bounds = bar.bounds
            meter.anchorPoint = CGPoint(x: 0.5, y: 0)
            meter.position = CGPoint(x: bar.bounds.midX, y: 0)
            bar.mask = meter
            root.addSublayer(bar)
            bars.append(bar)
            meters.append(meter)
        }

        needle.bounds = CGRect(x: 0, y: 0, width: 3 * k, height: (G.dial.height - 6) * k)
        needle.backgroundColor = rgb(0xFF3B2F)
        needle.shadowColor = rgb(0xFF3B2F)
        needle.shadowOpacity = 0.8
        needle.shadowRadius = 4 * k
        needle.shadowOffset = .zero
        root.addSublayer(needle)

        _ = addImageLayer(lighting(), frame: full)

        var glowing = bars.enumerated().map { i, bar in Glow(layer: bar, halo: i == 0 ? G.eq : nil, color: 0x3BFF7A) }
        if mood == .night {
            let dialGlow = addImageLayer(patch(G.dial) { drawDial($0, backlit: true) }, frame: G.dial)
            glowing.insert(Glow(layer: dialGlow, halo: G.dial, color: 0xFFB347), at: 0)
        }
        glowing.append(Glow(layer: needle))
        applyMood(lamps: [Lamp(center: CGPoint(x: 250, y: 440), radius: 430, strength: 0.75),
                          Lamp(center: CGPoint(x: 920, y: 560), radius: 380, strength: 0.35)],
                  glowing: glowing)
    }

    override func artworkDidChange(animated: Bool) {
        setContents(label, labelImage(), animated: animated)
        setContents(sleeve, Vinyl.sleeve(side: G.sleeve.width, art: artwork, unit: canvas.unit), animated: animated)
        backCover.isHidden = history.isEmpty
        if let previous = history.first {
            setContents(backCover, Vinyl.sleeve(side: G.backCover.width, art: previous, unit: canvas.unit * 0.7), animated: animated)
        }
    }

    override func trackInfoDidChange(animated: Bool) {
        setContents(label, labelImage(), animated: animated, duration: 0.5)
    }

    override func playbackDidChange(animated: Bool) {
        spinners.forEach { $0.set(spinning: isPlaying) }
        latch(keys[G.play], down: isPlaying, depth: G.keyTravel, animated: animated)
        if animated && !isPlaying { tap(keys[G.pause], depth: G.keyTravel) }
        isPlaying ? startMusic() : stopMusic(animated: animated)
    }

    override func trackSkipped(backwards: Bool) {
        tap(keys[backwards ? G.rewind : G.forward], depth: G.keyTravel)
    }

    override func progressDidChange(animated: Bool) {
        Tape.wind(packs, progress: progress, range: G.packRange, k: canvas.k, animated: animated)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(Self.progressTick)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        let x = G.dial.minX + G.dialPad + (G.dial.width - 2 * G.dialPad) * CGFloat(progress)
        needle.position = canvas.point(CGPoint(x: x, y: G.dial.midY))
        CATransaction.commit()
    }

    // MARK: - Motion

    /// Speaker thump at 116 bpm and a bouncing EQ. Pure Core Animation, so it costs no CPU.
    private func startMusic() {
        for cone in cones where cone.animation(forKey: "thump") == nil {
            let thump = CAKeyframeAnimation(keyPath: "transform.scale")
            thump.values = [1, 1.045, 1]
            thump.keyTimes = [0, 0.14, 1]
            thump.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            thump.duration = 60 / 116
            thump.repeatCount = .infinity
            thump.preferredFrameRateRange = .ambient
            cone.add(thump, forKey: "thump")
        }
        var rng = SplitMix64(seed: 99)
        for (i, meter) in meters.enumerated() where meter.animation(forKey: "eq") == nil {
            // Lows sit higher than highs, like a real spectrum.
            let ceiling = 1.0 - Double(i) / Double(G.eqBars) * 0.45
            var values = (0..<10).map { _ in Double.random(in: 0.18...ceiling, using: &rng) }
            values.append(values[0])
            let eq = CAKeyframeAnimation(keyPath: "transform.scale.y")
            eq.values = values
            eq.duration = .random(in: 1.6...2.6, using: &rng)
            eq.repeatCount = .infinity
            eq.preferredFrameRateRange = .ambient
            meter.add(eq, forKey: "eq")
        }
    }

    private func stopMusic(animated: Bool) {
        cones.forEach { $0.removeAnimation(forKey: "thump") }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.6)
        for meter in meters {
            meter.removeAnimation(forKey: "eq")
            meter.transform = CATransform3DMakeScale(1, 0.15, 1)
        }
        CATransaction.commit()
    }

    // MARK: - Static artwork

    private func background() -> CGImage {
        let unit = canvas.unit
        let wall = Texture.concrete(width: Int(1600 * unit * 0.5), height: Int(G.floorY * unit * 0.5), scale: Double(unit * 0.5),
                                    base: WoodStyle.hex(0xE2AD8C), seed: 51)
        let floor = Texture.concrete(width: Int(1600 * unit * 0.5), height: Int((1040 - G.floorY) * unit * 0.5),
                                     scale: Double(unit * 0.5), base: WoodStyle.hex(0x8A7F76), seed: 52)
        let sun = mood == .night ? nil : sunlight()
        return Draw.image(size: canvas.size, ppu: canvas.scale) { ctx in
            canvas.enterDesignSpace(ctx)
            let wallRect = CGRect(x: 0, y: 0, width: 1600, height: G.floorY)
            Draw.upright(ctx, wall, in: wallRect)
            ctx.drawLinearGradient(makeGradient([(0, white(1, 0.06)), (0.7, white(0, 0)), (1, white(0, 0.22))]),
                                   start: .zero, end: CGPoint(x: 0, y: G.floorY), options: [])
            if let sun { Draw.upright(ctx, sun, in: wallRect) }

            // Boombox and record shadows on the wall, thrown right by the low sun.
            Draw.castShadow(ctx, .rounded(G.body, 34), dx: 56, dy: -4, blur: 34, color: white(0, 0.28), unit: unit)
            Draw.castShadow(ctx, handlePath(), dx: 56, dy: -4, blur: 20, color: white(0, 0.22), unit: unit)

            // Skirting board and floor.
            let floorRect = CGRect(x: 0, y: G.floorY, width: 1600, height: 1040 - G.floorY)
            Draw.upright(ctx, floor, in: floorRect)
            ctx.drawLinearGradient(makeGradient([(0, white(0, 0.35)), (0.2, white(0, 0.05)), (1, white(0, 0.3))]),
                                   start: CGPoint(x: 0, y: floorRect.minY), end: CGPoint(x: 0, y: floorRect.maxY), options: [])
            let skirting = CGRect(x: 0, y: G.floorY - 24, width: 1600, height: 26)
            ctx.fill(CGPath(rect: skirting, transform: nil), linear: makeGradient([(0, rgb(0xF2E7DB)), (1, rgb(0xD9CBBE))]),
                     from: CGPoint(x: 0, y: skirting.minY), to: CGPoint(x: 0, y: skirting.maxY))
            ctx.line(CGPoint(x: 0, y: skirting.minY), CGPoint(x: 1600, y: skirting.minY), white(1, 0.6), width: 1.5)

            // Contact shadows on the floor.
            Draw.castShadow(ctx, .ellipse(CGRect(x: 470, y: 780, width: 900, height: 34)), dx: 10, dy: 4, blur: 18,
                            color: white(0, 0.6), unit: unit)
            Draw.castShadow(ctx, .ellipse(CGRect(x: 70, y: 778, width: 350, height: 22)), dx: 8, dy: 2, blur: 12,
                            color: white(0, 0.5), unit: unit)

            // Handle and rubber feet.
            ctx.setLineCap(.round)
            ctx.saveGState()
            Draw.shadow(ctx, dx: 0, dy: 4, blur: 6, color: white(0, 0.4), unit: unit)
            ctx.stroke(handlePath(), white(0.25), width: 18)
            ctx.restoreGState()
            ctx.stroke(handlePath(), white(0.62), width: 12)
            var up = CGAffineTransform(translationX: 0, y: -3)
            ctx.stroke(handlePath().copy(using: &up)!, white(0.95, 0.8), width: 3)
            for x in [545.0, 1265.0] as [CGFloat] {
                ctx.fill(.rounded(CGRect(x: x, y: 322, width: 30, height: 20), 4), white(0.12))
            }
            for x in [560.0, 1220.0] as [CGFloat] {
                ctx.fill(.rounded(CGRect(x: x, y: 786, width: 60, height: 12), 4), white(0.08))
            }
        }
    }

    private func handlePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 560, y: 330))
        p.addLine(to: CGPoint(x: 560, y: 282))
        p.addQuadCurve(to: CGPoint(x: 592, y: 252), control: CGPoint(x: 560, y: 252))
        p.addLine(to: CGPoint(x: 1248, y: 252))
        p.addQuadCurve(to: CGPoint(x: 1280, y: 282), control: CGPoint(x: 1280, y: 252))
        p.addLine(to: CGPoint(x: 1280, y: 330))
        return p
    }

    /// Late-afternoon window light on the wall, blurred soft.
    private func sunlight() -> CGImage {
        let img = Draw.image(size: CGSize(width: 1600, height: G.floorY), ppu: 0.25) { ctx in
            func window(_ origin: CGPoint, _ u: CGVector, _ v: CGVector, alpha: CGFloat) {
                func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
                    CGPoint(x: origin.x + u.dx * a + v.dx * b, y: origin.y + u.dy * a + v.dy * b)
                }
                for (a0, a1) in [(0.0, 0.47), (0.53, 1.0)] as [(CGFloat, CGFloat)] {
                    for (b0, b1) in [(0.0, 0.48), (0.52, 1.0)] as [(CGFloat, CGFloat)] {
                        ctx.fill(.polygon([p(a0, b0), p(a1, b0), p(a1, b1), p(a0, b1)]),
                                 rgb(mood == .sunset ? 0xFFB072 : 0xFFE0B0, alpha * (mood == .sunset ? 1.3 : 1)))
                    }
                }
            }
            window(CGPoint(x: 1160, y: 60), CGVector(dx: 420, dy: -40), CGVector(dx: 70, dy: 520), alpha: 0.42)
            window(CGPoint(x: -120, y: 110), CGVector(dx: 420, dy: -30), CGVector(dx: 60, dy: 500), alpha: 0.3)
        }
        return Draw.blur(img, sigma: 2.5)
    }

    private func keyImage(_ i: Int) -> CGImage {
        patch(G.key(i)) { ctx in
            let key = G.key(i)
            let face = CGPath(roundedRect: key, cornerWidth: 6, cornerHeight: 6, transform: nil)
            let isRecord = i == 0
            ctx.fill(face, linear: makeGradient(isRecord ? [(0, rgb(0xE0564B)), (1, rgb(0x9E2B24))]
                                                         : [(0, white(0.92)), (1, white(0.62))]),
                     from: CGPoint(x: 0, y: key.minY), to: CGPoint(x: 0, y: key.maxY))
            ctx.stroke(.rounded(key.insetBy(dx: 0.5, dy: 0.5), 6), white(0, 0.3), width: 1)
            ctx.line(CGPoint(x: key.minX + 4, y: key.minY + 2), CGPoint(x: key.maxX - 4, y: key.minY + 2), white(1, 0.7), width: 1.5)
            Draw.text(G.keyGlyphs[i], at: CGPoint(x: key.midX, y: key.minY + 7), size: 12, weight: .bold,
                      color: isRecord ? white(1, 0.9) : white(0.2, 0.8), centered: true)
        }
    }

    private func drawBody(_ ctx: CGContext) {
        let unit = canvas.unit
        let b = G.body, p = G.panel
        ctx.fill(.rounded(b, 34), linear: makeGradient([(0, rgb(0x3B3D42)), (1, rgb(0x1C1D20))]),
                 from: CGPoint(x: 0, y: b.minY), to: CGPoint(x: 0, y: b.maxY))
        ctx.stroke(.rounded(b.insetBy(dx: 1.5, dy: 1.5), 33), white(1, 0.18), width: 2)

        // Brushed aluminium front.
        let panel = CGPath.rounded(p, 20)
        ctx.fill(panel, linear: makeGradient([(0, rgb(0xDDE0E4)), (0.5, rgb(0xC4C8CD)), (1, rgb(0xA3A8AE))]),
                 from: CGPoint(x: 0, y: p.minY), to: CGPoint(x: 0, y: p.maxY))
        ctx.saveGState()
        ctx.addPath(panel)
        ctx.clip()
        let brushed = Texture.brushed(strength: 0.08)
        let tile = CGFloat(brushed.width) / unit
        ctx.draw(brushed, in: CGRect(x: 0, y: 0, width: tile, height: tile), byTiling: true)
        ctx.restoreGState()
        ctx.stroke(.rounded(p.insetBy(dx: 1, dy: 1), 19), white(1, 0.6), width: 1.5)

        drawDial(ctx, backlit: false)

        // Tweeters.
        for t in G.tweeters {
            ctx.fill(.ellipse(CGRect(center: t, radius: 24)), radial: makeGradient([(0, white(0.97)), (1, white(0.5))]),
                     center: CGPoint(x: t.x - 6, y: t.y - 8), radius: 30)
            ctx.fill(.ellipse(CGRect(center: t, radius: 15)), radial: makeGradient([(0, white(0.35)), (1, white(0.04))]),
                     center: CGPoint(x: t.x - 4, y: t.y - 5), radius: 17)
        }

        // Speaker rings and rubber surrounds; the cones themselves are separate layers.
        for c in G.speakers {
            ctx.saveGState()
            Draw.shadow(ctx, dx: 0, dy: 3, blur: 6, color: white(0, 0.4), unit: unit)
            ctx.fill(.ellipse(CGRect(center: c, radius: G.speakerRing)),
                     radial: makeGradient([(0, white(0.98)), (0.7, white(0.78)), (1, white(0.48))]),
                     center: CGPoint(x: c.x - 40, y: c.y - 50), radius: G.speakerRing * 1.3)
            ctx.restoreGState()
            ctx.fill(.ellipse(CGRect(center: c, radius: G.surround)),
                     radial: makeGradient([(0, rgb(0x2B2B2E)), (0.82, rgb(0x2B2B2E)), (0.9, rgb(0x3A3A3E)), (1, rgb(0x111113))]),
                     center: c, radius: G.surround)
            ctx.addArc(center: c, radius: (G.surround + G.cone) / 2, startAngle: .pi * 1.05, endAngle: .pi * 1.45, clockwise: false)
            ctx.setStrokeColor(white(1, 0.14))
            ctx.setLineWidth(6)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }

        // EQ display.
        ctx.fill(.rounded(G.eq, 5), rgb(0x0A0D0B))
        for i in 1..<4 {
            let y = G.eq.minY + G.eq.height * CGFloat(i) / 4
            ctx.line(CGPoint(x: G.eq.minX + 4, y: y), CGPoint(x: G.eq.maxX - 4, y: y), rgb(0x3BFF7A, 0.06), width: 1)
        }
        ctx.stroke(.rounded(G.eq.insetBy(dx: -2, dy: -2), 6), white(1, 0.5), width: 1.5)

        // Cassette door with the tape inside.
        let door = G.door
        ctx.stroke(.rounded(door.insetBy(dx: -3, dy: -3), 12), white(1, 0.55), width: 2)
        ctx.fill(.rounded(door, 10), rgb(0x121315))
        let s = G.shell
        ctx.fill(.rounded(s, 6), linear: makeGradient([(0, rgb(0x34353A)), (1, rgb(0x232427))]),
                 from: CGPoint(x: 0, y: s.minY), to: CGPoint(x: 0, y: s.maxY))
        let head = CGPath.polygon([CGPoint(x: s.minX + 38, y: s.maxY), CGPoint(x: s.minX + 50, y: s.maxY - 18),
                                   CGPoint(x: s.maxX - 50, y: s.maxY - 18), CGPoint(x: s.maxX - 38, y: s.maxY)])
        ctx.fill(head, rgb(0x2C2D31))
        for pt in [CGPoint(x: s.minX + 7, y: s.minY + 7), CGPoint(x: s.maxX - 7, y: s.minY + 7),
                   CGPoint(x: s.minX + 7, y: s.maxY - 7), CGPoint(x: s.maxX - 7, y: s.maxY - 7)] {
            ctx.fill(.ellipse(CGRect(center: pt, radius: 2.4)), white(0.55))
        }
        ctx.fill(.rounded(G.tapeWindow, G.tapeWindow.height / 2), rgb(0x0C0D0F))

        // Knobs.
        for knob in G.knobs {
            let c = knob.center
            Draw.castShadow(ctx, .ellipse(CGRect(center: c, radius: 19)), dx: 0, dy: 3, blur: 4, color: white(0, 0.45), unit: unit)
            ctx.fill(.ellipse(CGRect(center: c, radius: 19)), radial: makeGradient([(0, white(0.95)), (1, white(0.45))]),
                     center: CGPoint(x: c.x - 5, y: c.y - 6), radius: 24)
            for j in 0..<24 {
                let a = CGFloat(j) / 24 * 2 * .pi
                ctx.line(CGPoint(x: c.x + cos(a) * 16, y: c.y + sin(a) * 16), CGPoint(x: c.x + cos(a) * 19, y: c.y + sin(a) * 19),
                         white(0, 0.2), width: 1)
            }
            ctx.fill(.ellipse(CGRect(center: CGPoint(x: c.x + 8, y: c.y - 8), radius: 2.5)), rgb(0xFF5A3D))
            Draw.text(knob.label, at: CGPoint(x: c.x, y: c.y + 24), size: 8, weight: .bold, color: white(0.2, 0.7), kern: 1.5, centered: true)
        }

        Draw.text("PLATTER", at: CGPoint(x: b.midX, y: 704), size: 24, weight: .heavy, color: rgb(0x2A2B2E), kern: 4, centered: true)
        Draw.text("STEREO RADIO CASSETTE", at: CGPoint(x: b.midX, y: 736), size: 8.5, weight: .bold,
                  color: white(0.2, 0.65), kern: 2, centered: true)
    }

    /// The tuning scale; `backlit` is the night version, glowing amber.
    private func drawDial(_ ctx: CGContext, backlit: Bool) {
        let d = G.dial
        if backlit {
            ctx.fill(.rounded(d, 6), linear: makeGradient([(0, rgb(0x5A3410)), (0.5, rgb(0x7A4A16)), (1, rgb(0x4A2A0C))]),
                     from: CGPoint(x: 0, y: d.minY), to: CGPoint(x: 0, y: d.maxY))
        } else {
            ctx.fill(.rounded(d, 6), rgb(0x101317))
        }
        let ink = backlit ? rgb(0xFFE9C4) : white(1, 0.45)
        let scaleWidth = d.width - 2 * G.dialPad
        for t in 0...40 {
            let x = d.minX + G.dialPad + scaleWidth * CGFloat(t) / 40
            ctx.line(CGPoint(x: x, y: d.maxY - 4), CGPoint(x: x, y: d.maxY - (t % 5 == 0 ? 12 : 7)), ink, width: 1)
        }
        for (i, f) in ["88", "92", "96", "100", "104", "108"].enumerated() {
            Draw.text(f, at: CGPoint(x: d.minX + G.dialPad + scaleWidth * CGFloat(i) / 5, y: d.minY + 3), size: 9.5,
                      weight: .semibold, color: backlit ? rgb(0xFFF1D8) : white(1, 0.7), centered: true)
        }
        Draw.text("FM", at: CGPoint(x: d.minX + 8, y: d.minY + 3), size: 9, weight: .bold, color: rgb(0xFF8A3D))
        Draw.text("MHz", at: CGPoint(x: d.maxX - 24, y: d.minY + 4), size: 8, weight: .bold,
                  color: backlit ? rgb(0xFFE9C4) : white(1, 0.5))
    }

    private func coneArt() -> CGImage {
        let r = G.cone
        return Draw.image(size: CGSize(width: 2 * r, height: 2 * r), ppu: canvas.unit) { ctx in
            let c = CGPoint(x: r, y: r)
            ctx.fill(.ellipse(CGRect(center: c, radius: r)), radial: makeGradient([(0, rgb(0x3A3A3F)), (0.35, rgb(0x232327)), (1, rgb(0x141416))]),
                     center: CGPoint(x: c.x - 10, y: c.y - 14), radius: r)
            for i in 1..<7 {
                ctx.stroke(.ellipse(CGRect(center: c, radius: r * (0.3 + 0.1 * CGFloat(i)))), white(1, 0.035), width: 1.4)
            }
            ctx.fill(.ellipse(CGRect(center: c, radius: 36)), radial: makeGradient([(0, white(0.98)), (0.6, white(0.7)), (1, white(0.35))]),
                     center: CGPoint(x: c.x - 9, y: c.y - 11), radius: 44)
            ctx.stroke(.ellipse(CGRect(center: c, radius: 36)), white(0, 0.4), width: 1.5)
        }
    }

    private func eqBarArt() -> CGImage {
        let inner = G.eq.insetBy(dx: 8, dy: 6)
        let size = CGSize(width: inner.width / CGFloat(G.eqBars) - 4, height: inner.height)
        return Draw.image(size: size, ppu: canvas.unit) { ctx in
            let segments = 7
            let h = size.height / CGFloat(segments)
            for i in 0..<segments {
                // Drawn top-down: the top segment is red, then amber, the rest green.
                let color = i == 0 ? rgb(0xFF4A3D) : (i == 1 ? rgb(0xFFC23D) : rgb(0x3BFF7A))
                ctx.fill(CGPath(rect: CGRect(x: 0, y: CGFloat(i) * h + 0.6, width: size.width, height: h - 1.2), transform: nil), color)
            }
        }
    }

    private func drawDoorGlass(_ ctx: CGContext) {
        let w = G.door
        ctx.saveGState()
        ctx.addPath(.rounded(w, 10))
        ctx.clip()
        ctx.fill(CGPath(rect: w, transform: nil), white(0, 0.22))
        ctx.fill(.polygon([CGPoint(x: w.minX + 20, y: w.minY), CGPoint(x: w.minX + 80, y: w.minY),
                           CGPoint(x: w.minX + 20, y: w.maxY), CGPoint(x: w.minX - 40, y: w.maxY)]), white(1, 0.08))
        ctx.stroke(.rounded(w.insetBy(dx: 1.5, dy: 1.5), 9), white(0, 0.5), width: 3)
        ctx.restoreGState()
    }

    private func lighting() -> CGImage {
        let img = Draw.image(size: Canvas.design, ppu: 0.25) { ctx in
            ctx.drawLinearGradient(makeGradient([(0, rgb(0xFF9A4A, 0.10)), (0.5, rgb(0xFF9A4A, 0)), (1, rgb(0x5A2A40, 0.10))]),
                                   start: .zero, end: CGPoint(x: 1600, y: 0), options: [])
            ctx.drawRadialGradient(makeGradient([(0, white(0, 0)), (1, white(0, 0.35))]),
                                   startCenter: CGPoint(x: 900, y: 560), startRadius: 450,
                                   endCenter: CGPoint(x: 900, y: 560), endRadius: 1050, options: [.drawsAfterEndLocation])
        }
        return Draw.blur(img, sigma: 3)
    }

    private func labelImage() -> CGImage {
        let text = [title, artist].filter { !$0.isEmpty }.joined(separator: " — ")
        return Tape.label(G.label, window: G.tapeWindow, art: artwork, text: text, s: 0.42, unit: canvas.unit)
    }
}
