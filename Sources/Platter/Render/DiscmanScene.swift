import AppKit
import QuartzCore

/// Top-down: a portable CD player on concrete, the disc printed with the cover spinning under a
/// smoked lid, the jewel case beside it and earbuds trailing off.
final class DiscmanScene: DesktopScene {
    private enum G {
        static let center = CGPoint(x: 1030, y: 500)
        static let bodyRadius: CGFloat = 300
        /// The lid sits a little above centre to leave room for the display and keys.
        static let lidCenter = CGPoint(x: 1030, y: 470)
        static let lidRadius: CGFloat = 224
        static let discRadius: CGFloat = 207
        static let lcd = CGRect(x: 950, y: 712, width: 160, height: 46)
        static let jack = CGPoint(x: 752, y: 600)
        static let jewelCase = CGRect(x: 128, y: 286, width: 470, height: 418)
        static let caseAngle: CGFloat = 0.06
        /// Round keys either side of the display: previous, stop, play/pause, next.
        static let keys: [(x: CGFloat, glyph: String)] = [(880, "◀◀"), (918, "■"), (1142, "▶❚❚"), (1180, "▶▶")]
        static let previous = 0, stop = 1, playPause = 2, next = 3
        static var keyY: CGFloat { lcd.midY }
        static let keyRadius: CGFloat = 14
    }

    private let disc = CALayer()
    private let lcd = CALayer()
    private let jewelCase = CALayer()
    private var keys: [CALayer] = []
    private lazy var spinner = Spinner(layer: disc, period: 2.8)

    override func build() {
        let full = CGRect(origin: .zero, size: Canvas.design)
        _ = addImageLayer(background(), frame: full)

        disc.frame = canvas.rect(CGRect(center: G.lidCenter, radius: G.discRadius))
        root.addSublayer(disc)
        let lidRect = CGRect(center: G.lidCenter, radius: G.lidRadius + 2)
        _ = addImageLayer(patch(lidRect) { drawLid($0) }, frame: lidRect)

        lcd.frame = canvas.rect(G.lcd)
        root.addSublayer(lcd)
        keys = G.keys.map { key in
            let rect = CGRect(center: CGPoint(x: key.x, y: G.keyY), radius: G.keyRadius + 4)
            return addImageLayer(patch(rect) { drawKey($0, x: key.x, glyph: key.glyph) }, frame: rect)
        }

        let k = canvas.k
        jewelCase.bounds = CGRect(x: 0, y: 0, width: G.jewelCase.width * k, height: G.jewelCase.height * k)
        jewelCase.position = canvas.point(G.jewelCase.center)
        jewelCase.transform = CATransform3DMakeRotation(G.caseAngle, 0, 0, 1)
        applyShadow(jewelCase, dx: -10, dy: 18, blur: 22, opacity: 0.4)
        root.addSublayer(jewelCase)

        _ = addImageLayer(lighting(), frame: full)
        // The LCD is backlit, so it stays readable in the dark.
        applyMood(lamps: [Lamp(center: CGPoint(x: 980, y: 480), radius: 450), Lamp(center: CGPoint(x: 360, y: 500), radius: 300, strength: 0.4)],
                  glowing: [Glow(layer: lcd, halo: G.lcd, color: 0x9CFF8A)])
    }

    override func artworkDidChange(animated: Bool) {
        setContents(disc, discImage(), animated: animated)
        setContents(jewelCase, caseImage(), animated: animated)
    }

    override func playbackDidChange(animated: Bool) {
        spinner.set(spinning: isPlaying)
        lcd.contents = lcdImage()
        if animated { squeeze(keys[G.playPause]) }
    }

    override func trackSkipped(backwards: Bool) {
        squeeze(keys[backwards ? G.previous : G.next])
    }

    override func progressDidChange(animated: Bool) {
        lcd.contents = lcdImage()
    }

    // MARK: - Static artwork

    private func background() -> CGImage {
        let unit = canvas.unit
        let concrete = Texture.concrete(width: Int(1600 * unit * 0.5), height: Int(1040 * unit * 0.5),
                                        scale: Double(unit * 0.5), base: WoodStyle.hex(0xD4D0C9), seed: 41)
        return Draw.image(size: canvas.size, ppu: canvas.scale) { ctx in
            canvas.enterDesignSpace(ctx)
            Draw.upright(ctx, concrete, in: CGRect(origin: .zero, size: Canvas.design))
            drawEarbuds(ctx, unit: unit)
            drawPlayer(ctx, unit: unit)
        }
    }

    private func drawEarbuds(_ ctx: CGContext, unit: CGFloat) {
        let buds = [CGPoint(x: 600, y: 868), CGPoint(x: 712, y: 930)]
        let split = CGPoint(x: 700, y: 790)
        ctx.setLineCap(.round)
        for (i, bud) in buds.enumerated() {
            let wire = CGMutablePath()
            wire.move(to: bud)
            wire.addCurve(to: split, control1: CGPoint(x: bud.x + (i == 0 ? 60 : -10), y: bud.y - 40),
                          control2: CGPoint(x: split.x - 20, y: split.y + 50))
            ctx.saveGState()
            Draw.shadow(ctx, dx: -3, dy: 5, blur: 4, color: white(0, 0.35), unit: unit)
            ctx.stroke(wire, white(0.96), width: 4)
            ctx.restoreGState()
        }
        let lead = CGMutablePath()
        lead.move(to: split)
        lead.addCurve(to: G.jack, control1: CGPoint(x: 640, y: 720), control2: CGPoint(x: 700, y: 610))
        ctx.saveGState()
        Draw.shadow(ctx, dx: -3, dy: 5, blur: 4, color: white(0, 0.35), unit: unit)
        ctx.stroke(lead, white(0.96), width: 4.5)
        ctx.restoreGState()
        ctx.fill(.rounded(CGRect(x: split.x - 7, y: split.y - 10, width: 14, height: 20), 4), white(0.9))

        for (i, bud) in buds.enumerated() {
            let shell = CGRect(center: bud, radius: 27)
            Draw.castShadow(ctx, .ellipse(shell), dx: -4, dy: 7, blur: 8, color: white(0, 0.4), unit: unit)
            ctx.fill(.ellipse(shell), radial: makeGradient([(0, white(1)), (1, white(0.82))]),
                     center: CGPoint(x: bud.x + 6, y: bud.y - 8), radius: 32)
            ctx.fill(.ellipse(CGRect(center: bud, radius: 15)), white(0.35))
            for j in 0..<12 {
                let a = CGFloat(j) / 12 * 2 * .pi + CGFloat(i)
                ctx.fill(.ellipse(CGRect(center: CGPoint(x: bud.x + cos(a) * 8, y: bud.y + sin(a) * 8), radius: 1.4)), white(0.15))
            }
        }
    }

    private func drawPlayer(_ ctx: CGContext, unit: CGFloat) {
        let c = G.center, r = G.bodyRadius
        let body = CGPath.ellipse(CGRect(center: c, radius: r))

        // Jack plug on the rim.
        ctx.fill(.rounded(CGRect(x: G.jack.x - 22, y: G.jack.y - 9, width: 34, height: 18), 6), white(0.85))

        Draw.castShadow(ctx, body, dx: -16, dy: 24, blur: 40, color: white(0, 0.5), unit: unit)
        Draw.castShadow(ctx, body, dx: -3, dy: 4, blur: 6, color: white(0, 0.45), unit: unit)
        ctx.fill(body, radial: makeGradient([(0, rgb(0xF2F3F5)), (0.75, rgb(0xCDD1D5)), (1, rgb(0xA4AAB0))]),
                 center: CGPoint(x: c.x - 70, y: c.y - 90), radius: r * 1.2)
        // Anodised rim.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(center: c, radius: r))
        ctx.addEllipse(in: CGRect(center: c, radius: r - 18))
        ctx.clip(using: .evenOdd)
        ctx.drawConicGradient(makeGradient([
            (0, white(0.62)), (0.15, white(0.95)), (0.3, white(0.7)), (0.5, white(0.55)),
            (0.65, white(0.92)), (0.8, white(0.66)), (1, white(0.62)),
        ]), center: c, angle: 0.4)
        ctx.restoreGState()
        ctx.stroke(.ellipse(CGRect(center: c, radius: r - 18)), white(0, 0.18), width: 1.2)
        ctx.stroke(.ellipse(CGRect(center: c, radius: r - 1)), white(0, 0.35), width: 1.4)

        // Lid well.
        ctx.fill(.ellipse(CGRect(center: G.lidCenter, radius: G.lidRadius + 8)), white(0.62))
        ctx.fill(.ellipse(CGRect(center: G.lidCenter, radius: G.lidRadius)), rgb(0x1B1C1F))

        Draw.text("PLATTER", at: CGPoint(x: c.x, y: c.y - r + 19), size: 12, weight: .heavy,
                  color: white(0.25), kern: 6, centered: true)

        // LCD bezel and buttons.
        ctx.fill(.rounded(G.lcd.insetBy(dx: -6, dy: -6), 10), white(0.2))
        // Recessed seats for the keys.
        for key in G.keys {
            ctx.fill(.ellipse(CGRect(center: CGPoint(x: key.x, y: G.keyY), radius: G.keyRadius + 2.5)), white(0.55))
        }
    }

    private func drawKey(_ ctx: CGContext, x: CGFloat, glyph: String) {
        let y = G.keyY, key = CGRect(center: CGPoint(x: x, y: y), radius: G.keyRadius)
        Draw.castShadow(ctx, .ellipse(key), dx: -1, dy: 2, blur: 3, color: white(0, 0.4), unit: canvas.unit)
        ctx.fill(.ellipse(key), radial: makeGradient([(0, white(0.48)), (1, white(0.22))]),
                 center: CGPoint(x: x - 3, y: y - 4), radius: 17)
        ctx.stroke(.ellipse(key), white(1, 0.25), width: 1)
        Draw.text(glyph, at: CGPoint(x: x, y: y - 5.5), size: 7.5, weight: .bold, color: white(1, 0.8), centered: true)
    }

    /// Smoked lid with an iridescent glint and the centre spindle cap.
    private func drawLid(_ ctx: CGContext) {
        let c = G.lidCenter, r = G.lidRadius
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(center: c, radius: r))
        ctx.clip()
        ctx.fill(.ellipse(CGRect(center: c, radius: r)), white(0, 0.14))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(center: c, radius: r))
        ctx.addEllipse(in: CGRect(center: c, radius: r * 0.42))
        ctx.clip(using: .evenOdd)
        ctx.drawConicGradient(makeGradient([
            (0.00, rgb(0xFF6AD5, 0)), (0.06, rgb(0xFF6AD5, 0.16)), (0.12, rgb(0x6AD5FF, 0.18)),
            (0.18, rgb(0x9DFF6A, 0.14)), (0.24, rgb(0xFFE36A, 0.12)), (0.32, rgb(0xFFE36A, 0)),
            (0.50, rgb(0xFF6AD5, 0)), (0.56, rgb(0x6AD5FF, 0.12)), (0.62, rgb(0xFF6AD5, 0.14)),
            (0.70, rgb(0xFFE36A, 0)), (1.00, rgb(0xFF6AD5, 0)),
        ]), center: c, angle: -0.6)
        ctx.restoreGState()
        ctx.addArc(center: c, radius: r * 0.86, startAngle: .pi * 1.05, endAngle: .pi * 1.38, clockwise: false)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(white(1, 0.35))
        ctx.setLineWidth(10)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.stroke(.ellipse(CGRect(center: c, radius: r - 1)), white(1, 0.3), width: 2)

        ctx.fill(.ellipse(CGRect(center: c, radius: 34)), radial: makeGradient([(0, white(0.97)), (0.8, white(0.72)), (1, white(0.5))]),
                 center: CGPoint(x: c.x - 8, y: c.y - 10), radius: 40)
        ctx.stroke(.ellipse(CGRect(center: c, radius: 22)), white(0, 0.2), width: 1.2)
        Draw.text("PUSH", at: CGPoint(x: c.x, y: c.y - 6), size: 8.5, weight: .bold, color: white(0, 0.4), kern: 1.4, centered: true)
    }

    private func lighting() -> CGImage {
        let img = Draw.image(size: Canvas.design, ppu: 0.25) { ctx in
            // A potted plant just out of frame throws soft leaf shadows over the top-right corner.
            var rng = SplitMix64(seed: 23)
            for _ in 0..<26 {
                ctx.saveGState()
                ctx.translateBy(x: .random(in: 1150...1700, using: &rng), y: .random(in: -80...260, using: &rng))
                ctx.rotate(by: .random(in: 0...CGFloat.pi, using: &rng))
                let l = CGFloat.random(in: 90...220, using: &rng)
                ctx.fill(.ellipse(CGRect(x: -l / 2, y: -l / 6, width: l, height: l / 3)), white(0, 0.2))
                ctx.restoreGState()
            }
            ctx.drawRadialGradient(makeGradient([(0, white(1, 0.10)), (1, white(1, 0))]),
                                   startCenter: CGPoint(x: 420, y: 260), startRadius: 0,
                                   endCenter: CGPoint(x: 420, y: 260), endRadius: 800, options: [])
            ctx.drawRadialGradient(makeGradient([(0, white(0, 0)), (1, white(0, 0.3))]),
                                   startCenter: CGPoint(x: 820, y: 500), startRadius: 450,
                                   endCenter: CGPoint(x: 820, y: 500), endRadius: 1050, options: [.drawsAfterEndLocation])
        }
        return Draw.blur(img, sigma: 4)
    }

    // MARK: - Dynamic artwork

    /// The disc: cover printed edge to edge, a silver outer lip and the clear centre ring.
    private func discImage() -> CGImage {
        let d = G.discRadius * 2
        return Draw.image(size: CGSize(width: d, height: d), ppu: canvas.unit) { ctx in
            let c = CGPoint(x: d / 2, y: d / 2), r = d / 2
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(center: c, radius: r))
            ctx.clip()
            ctx.drawConicGradient(makeGradient([(0, white(0.75)), (0.25, white(0.95)), (0.5, white(0.7)), (0.75, white(0.92)), (1, white(0.75))]),
                                  center: c, angle: 0)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(center: c, radius: r * 0.975))
            ctx.addEllipse(in: CGRect(center: c, radius: r * 0.36))
            ctx.clip(using: .evenOdd)
            if let artwork {
                Draw.aspectFill(ctx, artwork, in: CGRect(center: c, radius: r * 0.975))
            } else {
                ctx.fill(.ellipse(CGRect(center: c, radius: r)), rgb(0xE8E4DC))
                Draw.text("PLATTER", at: CGPoint(x: c.x, y: c.y - r * 0.62), size: 26, weight: .heavy,
                          color: rgb(0x5A4A3A), kern: 6, centered: true)
            }
            ctx.restoreGState()
            // Clear hub ring and spindle hole.
            ctx.fill(.ellipse(CGRect(center: c, radius: r * 0.36)), white(0.85, 0.55))
            ctx.stroke(.ellipse(CGRect(center: c, radius: r * 0.36)), white(0, 0.2), width: 1)
            ctx.stroke(.ellipse(CGRect(center: c, radius: r * 0.25)), white(1, 0.5), width: 1.5)
            ctx.fill(.ellipse(CGRect(center: c, radius: r * 0.065)), rgb(0x1B1C1F))
            // A printed tick so the spin reads even on flat covers.
            ctx.fill(.rounded(CGRect(x: c.x - 3, y: c.y - r * 0.95, width: 6, height: 18), 3), white(1, 0.5))
        }
    }

    private func lcdImage() -> CGImage {
        let rect = G.lcd
        return Draw.image(size: rect.size, ppu: canvas.unit) { ctx in
            let full = CGRect(origin: .zero, size: rect.size)
            ctx.fill(.rounded(full, 6), linear: makeGradient([(0, rgb(0xB6C4A8)), (1, rgb(0x98A88C))]),
                     from: .zero, to: CGPoint(x: 0, y: full.height))
            let ink = rgb(0x26301F, 0.85)
            if isPlaying {
                ctx.fill(.polygon([CGPoint(x: 14, y: 8), CGPoint(x: 26, y: 15), CGPoint(x: 14, y: 22)]), ink)
            } else {
                ctx.fill(CGPath(rect: CGRect(x: 14, y: 8, width: 4.5, height: 14), transform: nil), ink)
                ctx.fill(CGPath(rect: CGRect(x: 22, y: 8, width: 4.5, height: 14), transform: nil), ink)
            }
            Draw.text("ESP", at: CGPoint(x: 36, y: 6), size: 12, weight: .heavy, color: ink, kern: 1)
            Draw.text("CD", at: CGPoint(x: full.width - 36, y: 6), size: 12, weight: .heavy, color: ink, kern: 1)
            let segments = 14
            let lit = Int((Double(segments) * progress).rounded(.up))
            for i in 0..<segments {
                let seg = CGRect(x: 14 + CGFloat(i) * 9.4, y: 31, width: 7, height: 8)
                ctx.fill(CGPath(rect: seg, transform: nil), i < lit ? ink : rgb(0x26301F, 0.12))
            }
            ctx.stroke(.rounded(full.insetBy(dx: 0.5, dy: 0.5), 6), white(0, 0.3), width: 1)
        }
    }

    /// Jewel case: hinge strip on the left, booklet with the cover, scratched plastic glare.
    private func caseImage() -> CGImage {
        let size = G.jewelCase.size
        return Draw.image(size: size, ppu: canvas.unit) { ctx in
            let full = CGRect(origin: .zero, size: size)
            ctx.fill(.rounded(full, 5), rgb(0x2A2C30))
            let booklet = CGRect(x: 52, y: 10, width: size.width - 62, height: size.height - 20)
            if let artwork {
                Draw.aspectFill(ctx, artwork, in: booklet)
            } else {
                ctx.fill(CGPath(rect: booklet, transform: nil), rgb(0xD8CCB4))
            }
            // Hinge.
            let hinge = CGRect(x: 0, y: 0, width: 44, height: size.height)
            ctx.fill(CGPath(rect: hinge, transform: nil), linear: makeGradient([(0, white(0.16)), (0.6, white(0.32)), (1, white(0.12))]),
                     from: .zero, to: CGPoint(x: hinge.maxX, y: 0))
            for y in stride(from: CGFloat(16), to: size.height - 10, by: 9) {
                ctx.line(CGPoint(x: 8, y: y), CGPoint(x: 36, y: y), white(1, 0.08), width: 2)
            }
            ctx.fill(.polygon([CGPoint(x: size.width * 0.5, y: 0), CGPoint(x: size.width, y: 0),
                               CGPoint(x: size.width, y: size.height * 0.3), CGPoint(x: size.width * 0.2, y: size.height * 0.75),
                               CGPoint(x: 44, y: size.height * 0.75), CGPoint(x: 44, y: size.height * 0.6)]), white(1, 0.08))
            ctx.stroke(.rounded(full.insetBy(dx: 0.8, dy: 0.8), 5), white(1, 0.55), width: 1.6)
            ctx.stroke(CGPath(rect: booklet, transform: nil), white(0, 0.25), width: 1)
        }
    }
}
