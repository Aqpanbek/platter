import AppKit
import QuartzCore

/// Top-down: a portable cassette player on a felt desk mat. The tape's label is the album cover,
/// the reels turn while playing and tape winds from one spool to the other as the track goes on.
final class CassetteScene: DesktopScene {
    private enum G {
        static let body = CGRect(x: 740, y: 280, width: 640, height: 450)
        static let window = CGRect(x: 800, y: 316, width: 520, height: 296)
        static let shell = CGRect(x: 830, y: 334, width: 460, height: 262)
        static let label = CGRect(x: 852, y: 350, width: 416, height: 160)
        static let tapeWindow = CGRect(x: 905, y: 402, width: 310, height: 72)
        static let hubs = [CGPoint(x: 961, y: 438), CGPoint(x: 1159, y: 438)]
        static let hubRadius: CGFloat = 22
        static let packRange: ClosedRange<CGFloat> = 25...66
        static let jack = CGPoint(x: 1338, y: 282)
        static let jCard = CGRect(x: 205, y: 262, width: 310, height: 470)
        static let jCardAngle: CGFloat = 0.075
        /// Transport keys along the top edge: stop, rewind, play, fast-forward, record.
        static func key(_ i: Int) -> CGRect { CGRect(x: 812 + CGFloat(i) * 86, y: 252, width: 74, height: 50) }
        static let keyColors: [UInt32] = [0xC9CDD2, 0xC9CDD2, 0xE8823A, 0xC9CDD2, 0xC23B32]
        static let stop = 0, rewind = 1, play = 2, forward = 3
        static let keyTravel: CGFloat = 11
        /// Room around the body for its shadow.
        static let bodyPatch = body.insetBy(dx: -70, dy: -60)
    }

    private let label = CALayer()
    private let jCard = CALayer()
    private var packs: [CALayer] = []
    private var keys: [CALayer] = []
    private var spinners: [Spinner] = []

    override func build() {
        packs.removeAll()
        keys.removeAll()
        spinners.removeAll()
        let full = CGRect(origin: .zero, size: Canvas.design)
        _ = addImageLayer(background(), frame: full)

        // Keys sit under the body's top edge so pressing slides them in.
        for i in G.keyColors.indices {
            let key = addImageLayer(keyImage(i), frame: G.key(i))
            applyShadow(key, dx: -4, dy: 6, blur: 5, opacity: 0.45,
                        path: CGPath(roundedRect: key.bounds, cornerWidth: 6 * canvas.k, cornerHeight: 6 * canvas.k, transform: nil))
            keys.append(key)
        }
        _ = addImageLayer(patch(G.bodyPatch) { drawBody($0, unit: canvas.unit) }, frame: G.bodyPatch)

        let reels = Tape.reels(in: G.tapeWindow, hubs: G.hubs, hubRadius: G.hubRadius, canvas: canvas)
        root.addSublayer(reels.container)
        packs = reels.packs
        spinners = reels.hubs.map { Spinner(layer: $0, period: 3.4, clockwise: false) }

        label.frame = canvas.rect(G.label)
        root.addSublayer(label)
        _ = addImageLayer(patch(G.window) { drawGlass($0) }, frame: G.window)

        let k = canvas.k
        jCard.bounds = CGRect(x: 0, y: 0, width: G.jCard.width * k, height: G.jCard.height * k)
        jCard.position = canvas.point(G.jCard.center)
        jCard.transform = CATransform3DMakeRotation(G.jCardAngle, 0, 0, 1)
        applyShadow(jCard, dx: -10, dy: 18, blur: 20, opacity: 0.5)
        root.addSublayer(jCard)

        _ = addImageLayer(lighting(), frame: full)
        applyMood(lamps: [Lamp(center: CGPoint(x: 960, y: 450), radius: 480), Lamp(center: CGPoint(x: 360, y: 500), radius: 300, strength: 0.4)])
    }

    override func artworkDidChange(animated: Bool) {
        setContents(label, labelImage(), animated: animated)
        setContents(jCard, jCardImage(), animated: animated)
    }

    override func trackInfoDidChange(animated: Bool) {
        setContents(label, labelImage(), animated: animated, duration: 0.5)
        setContents(jCard, jCardImage(), animated: animated, duration: 0.5)
    }

    override func playbackDidChange(animated: Bool) {
        spinners.forEach { $0.set(spinning: isPlaying) }
        // Play latches down like on a real deck; pausing pops it up with a press of Stop.
        latch(keys[G.play], down: isPlaying, depth: G.keyTravel, animated: animated)
        if animated && !isPlaying { tap(keys[G.stop], depth: G.keyTravel) }
    }

    override func trackSkipped(backwards: Bool) {
        tap(keys[backwards ? G.rewind : G.forward], depth: G.keyTravel)
    }

    override func progressDidChange(animated: Bool) {
        Tape.wind(packs, progress: progress, range: G.packRange, k: canvas.k, animated: animated)
    }

    // MARK: - Static artwork

    private func background() -> CGImage {
        let unit = canvas.unit
        let felt = Texture.felt(width: Int(1600 * unit * 0.5), height: Int(1040 * unit * 0.5), scale: Double(unit * 0.5),
                                base: WoodStyle.hex(0x2E4A50), seed: 31)
        return Draw.image(size: canvas.size, ppu: canvas.scale) { ctx in
            canvas.enterDesignSpace(ctx)
            Draw.upright(ctx, felt, in: CGRect(origin: .zero, size: Canvas.design))
            drawHeadphones(ctx, unit: unit)
            drawWheel(ctx)
        }
    }

    private func drawHeadphones(_ ctx: CGContext, unit: CGFloat) {
        let padL = CGPoint(x: 150, y: 140), padR = CGPoint(x: 430, y: 92)

        // Cable from the right ear cup to the player's jack.
        let cable = CGMutablePath()
        cable.move(to: CGPoint(x: padR.x + 40, y: padR.y + 40))
        cable.addCurve(to: G.jack, control1: CGPoint(x: 760, y: 300), control2: CGPoint(x: 1180, y: 110))
        ctx.saveGState()
        Draw.shadow(ctx, dx: -4, dy: 7, blur: 5, color: white(0, 0.45), unit: unit)
        ctx.setLineCap(.round)
        ctx.stroke(cable, rgb(0x161616), width: 4.5)
        ctx.restoreGState()
        var up = CGAffineTransform(translationX: -0.8, y: -0.8)
        ctx.stroke(cable.copy(using: &up)!, white(1, 0.18), width: 1.2)

        // Headband arching off the top of the screen.
        let band = CGMutablePath()
        band.move(to: padL)
        band.addCurve(to: padR, control1: CGPoint(x: 40, y: -190), control2: CGPoint(x: 470, y: -230))
        ctx.saveGState()
        Draw.shadow(ctx, dx: -6, dy: 10, blur: 8, color: white(0, 0.5), unit: unit)
        ctx.stroke(band, rgb(0x2A2C30), width: 13)
        ctx.restoreGState()
        ctx.stroke(band, white(0.75, 0.6), width: 2.5)

        for p in [padL, padR] {
            let pad = CGRect(center: p, radius: 72)
            Draw.castShadow(ctx, .ellipse(pad), dx: -8, dy: 14, blur: 16, color: white(0, 0.5), unit: unit)
            ctx.fill(.ellipse(pad), radial: makeGradient([(0, rgb(0xF29A4A)), (0.7, rgb(0xE07428)), (1, rgb(0xB4561A))]),
                     center: CGPoint(x: p.x + 14, y: p.y - 16), radius: 84)
            // Foam pores.
            var rng = SplitMix64(seed: UInt64(p.x))
            for _ in 0..<160 {
                let a = CGFloat.random(in: 0...(2 * .pi), using: &rng), d = CGFloat.random(in: 0...68, using: &rng)
                ctx.fill(.ellipse(CGRect(center: CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d),
                                         radius: .random(in: 0.8...2.2, using: &rng))), white(0, 0.12))
            }
            ctx.fill(.ellipse(CGRect(center: p, radius: 20)), white(0, 0.18))
        }
    }

    private func keyImage(_ i: Int) -> CGImage {
        patch(G.key(i)) { ctx in
            let key = G.key(i), color = G.keyColors[i]
            ctx.fill(.rounded(key, 6), linear: makeGradient([(0, rgb(color)), (1, rgb(color, 0.85))]),
                     from: CGPoint(x: 0, y: key.minY), to: CGPoint(x: 0, y: key.maxY))
            ctx.stroke(.rounded(key.insetBy(dx: 0.5, dy: 0.5), 6), white(0, 0.25), width: 1)
            drawKeyGlyph(ctx, index: i, center: CGPoint(x: key.midX, y: key.minY + 14))
        }
    }

    /// The volume wheel peeking out from under the right edge.
    private func drawWheel(_ ctx: CGContext) {
        let wheel = CGRect(x: 1366, y: 372, width: 26, height: 160)
        ctx.fill(.rounded(wheel, 8), linear: makeGradient([(0, white(0.3)), (0.5, white(0.62)), (1, white(0.25))]),
                 from: CGPoint(x: wheel.minX, y: 0), to: CGPoint(x: wheel.maxX, y: 0))
        for y in stride(from: wheel.minY + 6, to: wheel.maxY - 4, by: 6) {
            ctx.line(CGPoint(x: wheel.minX + 6, y: y), CGPoint(x: wheel.maxX, y: y), white(0, 0.35), width: 1.4)
        }
    }

    private func drawBody(_ ctx: CGContext, unit: CGFloat) {
        let b = G.body
        let body = CGPath.rounded(b, 42)
        Draw.castShadow(ctx, body, dx: -18, dy: 26, blur: 40, color: white(0, 0.55), unit: unit)
        Draw.castShadow(ctx, body, dx: -3, dy: 4, blur: 6, color: white(0, 0.5), unit: unit)
        ctx.fill(body, linear: makeGradient([(0, rgb(0xE6E8EB)), (0.5, rgb(0xC3C8CE)), (1, rgb(0x9DA3AA))]),
                 from: b.origin, to: CGPoint(x: b.maxX, y: b.maxY))
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let brushed = Texture.brushed(strength: 0.09)
        let tile = CGFloat(brushed.width) / unit
        ctx.draw(brushed, in: CGRect(x: 0, y: 0, width: tile, height: tile), byTiling: true)
        // Blue stripe with the maker's name.
        let stripe = CGRect(x: b.minX, y: b.maxY - 94, width: b.width, height: 48)
        ctx.fill(CGPath(rect: stripe, transform: nil), linear: makeGradient([(0, rgb(0x3463B4)), (1, rgb(0x244A8C))]),
                 from: CGPoint(x: 0, y: stripe.minY), to: CGPoint(x: 0, y: stripe.maxY))
        ctx.restoreGState()
        Draw.text("PLATTER", at: CGPoint(x: b.minX + 44, y: stripe.minY + 10), size: 22, weight: .heavy,
                  color: white(1, 0.95), kern: 2)
        Draw.text("STEREO CASSETTE PLAYER", at: CGPoint(x: b.minX + 190, y: stripe.minY + 17), size: 11.5,
                  weight: .semibold, color: white(1, 0.8), kern: 2.6)
        Draw.text("AUTO REVERSE", at: CGPoint(x: b.maxX - 150, y: stripe.minY + 17), size: 11.5,
                  weight: .semibold, color: white(1, 0.8), kern: 2.2)
        ctx.stroke(.rounded(b.insetBy(dx: 2, dy: 2), 40), white(1, 0.55), width: 2)
        ctx.stroke(body, white(0, 0.35), width: 1.2)

        // Headphone jack.
        ctx.fill(.ellipse(CGRect(center: G.jack, radius: 11)), rgb(0xC9A04F))
        ctx.fill(.ellipse(CGRect(center: G.jack, radius: 6)), rgb(0x161616))

        // Recessed lid window and the cassette inside it.
        let w = G.window
        ctx.stroke(.rounded(w.insetBy(dx: -3, dy: -3), 23), white(1, 0.6), width: 2.5)
        ctx.fill(.rounded(w, 20), rgb(0x15181C))
        let s = G.shell
        ctx.fill(.rounded(s, 10), linear: makeGradient([(0, rgb(0x34353A)), (1, rgb(0x232427))]),
                 from: CGPoint(x: 0, y: s.minY), to: CGPoint(x: 0, y: s.maxY))
        ctx.stroke(.rounded(s.insetBy(dx: 1, dy: 1), 9), white(1, 0.08), width: 1)
        let head = CGPath.polygon([CGPoint(x: s.minX + 92, y: s.maxY), CGPoint(x: s.minX + 122, y: s.maxY - 46),
                                   CGPoint(x: s.maxX - 122, y: s.maxY - 46), CGPoint(x: s.maxX - 92, y: s.maxY)])
        ctx.fill(head, rgb(0x2C2D31))
        ctx.stroke(head, white(1, 0.06), width: 1)
        for x in [s.midX - 70, s.midX, s.midX + 70] {
            ctx.fill(.rounded(CGRect(x: x - 9, y: s.maxY - 30, width: 18, height: 14), 3), rgb(0x0F1012))
        }
        for p in [CGPoint(x: s.minX + 14, y: s.minY + 14), CGPoint(x: s.maxX - 14, y: s.minY + 14),
                  CGPoint(x: s.minX + 14, y: s.maxY - 14), CGPoint(x: s.maxX - 14, y: s.maxY - 14),
                  CGPoint(x: s.midX, y: s.maxY - 54)] {
            ctx.fill(.ellipse(CGRect(center: p, radius: 4.5)), white(0.55))
            ctx.line(CGPoint(x: p.x - 3, y: p.y), CGPoint(x: p.x + 3, y: p.y), white(0.2), width: 1)
        }
        // Dark well behind the spools.
        ctx.fill(.rounded(G.tapeWindow, G.tapeWindow.height / 2), rgb(0x0C0D0F))
    }

    private func drawKeyGlyph(_ ctx: CGContext, index: Int, center c: CGPoint) {
        let ink = white(0, 0.55)
        switch index {
        case 0: ctx.fill(CGPath(rect: CGRect(center: c, radius: 5), transform: nil), ink)
        case 1:
            ctx.fill(.polygon([CGPoint(x: c.x, y: c.y - 5), CGPoint(x: c.x - 8, y: c.y), CGPoint(x: c.x, y: c.y + 5)]), ink)
            ctx.fill(.polygon([CGPoint(x: c.x + 8, y: c.y - 5), CGPoint(x: c.x, y: c.y), CGPoint(x: c.x + 8, y: c.y + 5)]), ink)
        case 2: ctx.fill(.polygon([CGPoint(x: c.x - 5, y: c.y - 6), CGPoint(x: c.x + 7, y: c.y), CGPoint(x: c.x - 5, y: c.y + 6)]), ink)
        case 3:
            ctx.fill(.polygon([CGPoint(x: c.x - 8, y: c.y - 5), CGPoint(x: c.x, y: c.y), CGPoint(x: c.x - 8, y: c.y + 5)]), ink)
            ctx.fill(.polygon([CGPoint(x: c.x, y: c.y - 5), CGPoint(x: c.x + 8, y: c.y), CGPoint(x: c.x, y: c.y + 5)]), ink)
        default: ctx.fill(.ellipse(CGRect(center: c, radius: 5)), white(1, 0.7))
        }
    }

    /// Smoked lid plastic over the cassette.
    private func drawGlass(_ ctx: CGContext) {
        let w = G.window
        ctx.saveGState()
        ctx.addPath(.rounded(w, 20))
        ctx.clip()
        ctx.fill(CGPath(rect: w, transform: nil), white(0, 0.2))
        ctx.fill(.polygon([CGPoint(x: w.minX + 40, y: w.minY), CGPoint(x: w.minX + 190, y: w.minY),
                           CGPoint(x: w.minX + 60, y: w.maxY), CGPoint(x: w.minX - 90, y: w.maxY)]), white(1, 0.07))
        ctx.fill(.polygon([CGPoint(x: w.minX + 230, y: w.minY), CGPoint(x: w.minX + 270, y: w.minY),
                           CGPoint(x: w.minX + 140, y: w.maxY), CGPoint(x: w.minX + 100, y: w.maxY)]), white(1, 0.05))
        ctx.stroke(.rounded(w.insetBy(dx: 2, dy: 2), 18), white(0, 0.5), width: 4)
        ctx.restoreGState()
    }

    private func lighting() -> CGImage {
        let img = Draw.image(size: Canvas.design, ppu: 0.25) { ctx in
            ctx.drawRadialGradient(makeGradient([(0, rgb(0xFFE9C8, 0.14)), (1, rgb(0xFFE9C8, 0))]),
                                   startCenter: CGPoint(x: 520, y: 240), startRadius: 0,
                                   endCenter: CGPoint(x: 520, y: 240), endRadius: 900, options: [])
            ctx.drawRadialGradient(makeGradient([(0, white(0, 0)), (1, white(0, 0.42))]),
                                   startCenter: CGPoint(x: 820, y: 480), startRadius: 420,
                                   endCenter: CGPoint(x: 820, y: 480), endRadius: 1050, options: [.drawsAfterEndLocation])
        }
        return Draw.blur(img, sigma: 3)
    }

    // MARK: - Dynamic artwork

    private func labelImage() -> CGImage {
        let text = [title, artist].filter { !$0.isEmpty }.joined(separator: " — ")
        return Tape.label(G.label, window: G.tapeWindow, art: artwork, text: text, s: 1, unit: canvas.unit)
    }

    /// The cassette box: cover on top, title band below in the cover's own colour.
    private func jCardImage() -> CGImage {
        let size = G.jCard.size
        return Draw.image(size: size, ppu: canvas.unit) { ctx in
            let full = CGRect(origin: .zero, size: size)
            let inner = full.insetBy(dx: 9, dy: 9)
            ctx.fill(.rounded(full, 6), rgb(0xDCE1E4, 0.9))
            let art = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.width)
            let band = CGRect(x: inner.minX, y: art.maxY, width: inner.width, height: inner.maxY - art.maxY)
            let avg = artwork.map(Texture.averageColor) ?? SIMD3(60, 60, 64)
            ctx.fill(CGPath(rect: band, transform: nil),
                     CGColor(srgbRed: avg.x / 255, green: avg.y / 255, blue: avg.z / 255, alpha: 1))
            if let artwork {
                Draw.aspectFill(ctx, artwork, in: art)
            } else {
                ctx.fill(CGPath(rect: art, transform: nil), rgb(0xD8CCB4))
            }
            let luminance = (0.299 * avg.x + 0.587 * avg.y + 0.114 * avg.z) / 255
            let ink = luminance > 0.6 ? NSColor(calibratedWhite: 0.1, alpha: 0.9) : NSColor(calibratedWhite: 1, alpha: 0.92)
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: title.isEmpty ? "Side A" : title, attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: ink, .paragraphStyle: para,
            ]).draw(with: CGRect(x: band.minX + 16, y: band.minY + 18, width: band.width - 32, height: 30),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            NSAttributedString(string: artist, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.7),
                .paragraphStyle: para,
            ]).draw(with: CGRect(x: band.minX + 16, y: band.minY + 50, width: band.width - 32, height: 22),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            Draw.text("TYPE I · NORMAL POSITION", at: CGPoint(x: band.minX + 16, y: band.maxY - 26), size: 9,
                      weight: .semibold, color: ink.withAlphaComponent(0.5).cgColor, kern: 1.6)
            // Clear plastic: hinge bumps, glare and edges.
            for x in [inner.minX + 30, inner.maxX - 50] {
                ctx.fill(.rounded(CGRect(x: x, y: 2, width: 20, height: 9), 3), white(1, 0.45))
            }
            ctx.fill(.polygon([CGPoint(x: size.width * 0.55, y: 0), CGPoint(x: size.width, y: 0),
                               CGPoint(x: size.width, y: size.height * 0.25), CGPoint(x: size.width * 0.15, y: size.height * 0.62)]),
                     white(1, 0.08))
            ctx.stroke(.rounded(full.insetBy(dx: 0.8, dy: 0.8), 6), white(1, 0.7), width: 1.6)
            ctx.stroke(.rounded(inner, 2), white(0, 0.15), width: 1)
        }
    }
}
