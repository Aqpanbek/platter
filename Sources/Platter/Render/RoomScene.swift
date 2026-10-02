import AppKit
import QuartzCore

/// Front view of a desk against a wall: the album leans on a stand, the record spins on a deck,
/// recently played covers lie in a stack. `night` turns the sunlit room into a lamp-lit one.
final class RoomScene: DesktopScene {
    private enum G {
        static let deskTop: CGFloat = 545
        static let frame = CGRect(x: 770, y: -24, width: 432, height: 262)
        static let sleeve = CGRect(x: 112, y: 350, width: 382, height: 382)
        static let sleeveAngle: CGFloat = 0.022
        static let standFront = CGRect(x: 90, y: 724, width: 440, height: 70)
        static let plinthTop = [CGPoint(x: 562, y: 552), CGPoint(x: 1060, y: 552),
                                CGPoint(x: 1074, y: 654), CGPoint(x: 548, y: 654)]
        static let plinthFront = CGRect(x: 548, y: 654, width: 526, height: 122)
        static let platterCenter = CGPoint(x: 742, y: 606)
        static let platterRadius: CGFloat = 188
        static let recordCenter = CGPoint(x: 742, y: 601)
        static let recordRadius: CGFloat = 176
        static let tilt: CGFloat = 0.41
        static let pivot = CGPoint(x: 1000, y: 566)
        static let stylus = CGPoint(x: 826, y: 644)
        static let armPatch = CGRect(x: 770, y: 470, width: 290, height: 220)
        static let lampX: CGFloat = 1447
        static let bulb = CGPoint(x: 1447, y: 432)
        static let lampPatch = CGRect(x: 1330, y: 250, width: 236, height: 300)
        /// Covers lying on the stack, bottom first. Angles are layer rotations (counter-clockwise).
        static let prints: [(center: CGPoint, angle: CGFloat)] = [
            (CGPoint(x: 1332, y: 716), 0.075), (CGPoint(x: 1352, y: 707), -0.03),
        ]
        static let printSide: CGFloat = 370
    }

    private var night: Bool { mood == .night }
    private let sleeve = CALayer()
    private let disc = CALayer()
    private var prints: [CALayer] = []
    private lazy var spinner = Spinner(layer: disc)
    private var walnut: CGImage!

    override func build() {
        prints.removeAll()
        walnut = Texture.wood(width: 900, height: 170, style: .walnut) { nx, ny in (nx * 1.6, ny * 0.3) }
        let full = CGRect(origin: .zero, size: Canvas.design)
        _ = addImageLayer(background(), frame: full)

        let k = canvas.k
        sleeve.bounds = CGRect(x: 0, y: 0, width: G.sleeve.width * k, height: G.sleeve.height * k)
        sleeve.position = canvas.point(G.sleeve.center)
        sleeve.transform = CATransform3DMakeRotation(G.sleeveAngle, 0, 0, 1)
        applyShadow(sleeve, dx: night ? -20 : 22, dy: 2, blur: 26, opacity: night ? 0.5 : 0.32)
        root.addSublayer(sleeve)
        _ = addImageLayer(patch(G.standFront) { drawStandFront($0) }, frame: G.standFront)

        for spot in G.prints {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: G.printSide * k, height: G.printSide * k)
            l.position = canvas.point(spot.center)
            l.transform = CATransform3DConcat(CATransform3DMakeRotation(spot.angle, 0, 0, 1),
                                              CATransform3DMakeScale(1, G.tilt, 1))
            applyShadow(l, dx: night ? -6 : 8, dy: 6, blur: 5, opacity: 0.35)
            root.addSublayer(l)
            prints.append(l)
        }

        let r = G.recordRadius
        let deck = CALayer()
        deck.bounds = CGRect(x: 0, y: 0, width: 2 * r * k, height: 2 * r * k)
        deck.position = canvas.point(G.recordCenter)
        deck.transform = CATransform3DMakeScale(1, G.tilt, 1)
        disc.frame = deck.bounds
        deck.addSublayer(disc)
        let sheen = CALayer()
        sheen.frame = deck.bounds
        sheen.contents = Vinyl.sheen(diameter: 2 * r, unit: canvas.unit, strength: 1.4)
        deck.addSublayer(sheen)
        root.addSublayer(deck)

        _ = addImageLayer(patch(G.armPatch) { drawTonearm($0) }, frame: G.armPatch)

        if night {
            _ = addImageLayer(nightShade(), frame: full)
            _ = addImageLayer(lampHalo(), frame: full)
            _ = addImageLayer(patch(G.lampPatch) { drawLitShade($0) }, frame: G.lampPatch)
        } else {
            applyMood(lamps: [])
        }
    }

    override func artworkDidChange(animated: Bool) {
        setContents(sleeve, Vinyl.sleeve(side: G.sleeve.width, art: artwork, unit: canvas.unit), animated: animated)
        setContents(disc, Vinyl.disc(diameter: G.recordRadius * 2, art: artwork, unit: canvas.unit), animated: animated)
        for (i, layer) in prints.enumerated() {
            let index = prints.count - 1 - i  // the top print shows the most recent album
            let art = index < history.count ? history[index] : nil
            layer.isHidden = art == nil
            if let art {
                setContents(layer, Vinyl.sleeve(side: G.printSide, art: art, unit: canvas.unit * 0.7, border: 9),
                            animated: animated)
            }
        }
    }

    override func playbackDidChange(animated: Bool) {
        spinner.set(spinning: isPlaying)
    }

    // MARK: - Background

    private func background() -> CGImage {
        let unit = canvas.unit
        let desk = deskTexture(unit: unit)
        let sun = night ? nil : sunMask()
        return Draw.image(size: canvas.size, ppu: canvas.scale) { ctx in
            canvas.enterDesignSpace(ctx)
            drawWall(ctx, sun: sun)
            drawFrame(ctx, unit: unit)
            drawDesk(ctx, texture: desk)
            drawLamp(ctx, unit: unit)
            drawStandBack(ctx, unit: unit)
            drawSheets(ctx, unit: unit)
            drawTurntable(ctx, unit: unit)
        }
    }

    private func drawWall(_ ctx: CGContext, sun: CGImage?) {
        let wall = CGRect(x: 0, y: 0, width: 1600, height: G.deskTop + 2)
        let wallPath = CGPath(rect: wall, transform: nil)
        if let sun {
            ctx.fill(wallPath, rgb(mood == .sunset ? 0xB8987A : 0xC1AB8B))
            ctx.saveGState()
            Draw.clip(ctx, toMask: sun, in: wall)
            ctx.fill(wallPath, rgb(mood == .sunset ? 0xFFC283 : 0xF7E8CB))
            ctx.restoreGState()
        } else {
            ctx.fill(wallPath, rgb(0xD5C5A9))
        }
        ctx.saveGState()
        ctx.clip(to: wall)
        ctx.drawLinearGradient(makeGradient([(0, white(0, 0.14)), (0.45, white(0, 0)), (0.88, white(0, 0)), (1, white(0, 0.32))]),
                               start: .zero, end: CGPoint(x: 0, y: wall.maxY), options: [])
        ctx.restoreGState()
    }

    /// Sunlight through a mullioned window, with a few leaves in the way. White = lit.
    private func sunMask() -> CGImage {
        let size = CGSize(width: 1600, height: G.deskTop + 2)
        let mask = Draw.mask(size: size, ppu: 0.25) { ctx in
            func w(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: -90 + 1120 * u - 160 * v, y: 10 + 250 * u + 610 * v)
            }
            let cols: [(CGFloat, CGFloat)] = [(0, 0.31), (0.345, 0.655), (0.69, 1)]
            let rows: [(CGFloat, CGFloat)] = [(0, 0.46), (0.51, 1)]
            for (u0, u1) in cols {
                for (v0, v1) in rows {
                    ctx.fill(.polygon([w(u0, v0), w(u1, v0), w(u1, v1), w(u0, v1)]), white(1 - 0.42 * u0))
                }
            }
            var rng = SplitMix64(seed: 11)
            for _ in 0..<52 {
                let c = CGPoint(x: .random(in: -60...360, using: &rng), y: .random(in: -10...320, using: &rng))
                let len = CGFloat.random(in: 26...74, using: &rng)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: .random(in: 0...CGFloat.pi, using: &rng))
                ctx.fill(.ellipse(CGRect(x: -len / 2, y: -len * 0.16, width: len, height: len * 0.32)), white(0))
                ctx.restoreGState()
            }
            for _ in 0..<7 {
                let s = CGMutablePath()
                let a = CGPoint(x: .random(in: -40...300, using: &rng), y: .random(in: 0...300, using: &rng))
                s.move(to: a)
                s.addQuadCurve(to: CGPoint(x: a.x + .random(in: -40...120, using: &rng), y: a.y + .random(in: 60...160, using: &rng)),
                               control: CGPoint(x: a.x + .random(in: 0...80, using: &rng), y: a.y + 40))
                ctx.stroke(s, white(0), width: 4)
            }
        }
        return Draw.blur(mask, sigma: 2.4, gray: true)
    }

    private func drawFrame(_ ctx: CGContext, unit: CGFloat) {
        let f = G.frame
        let framePath = CGPath(rect: f, transform: nil)
        Draw.castShadow(ctx, framePath, dx: night ? -8 : 16, dy: 18, blur: 24, color: white(0, 0.38), unit: unit)
        ctx.fill(framePath, linear: makeGradient([(0, rgb(0x5B3A21)), (0.5, rgb(0x4A2E1A)), (1, rgb(0x34200F))]),
                 from: CGPoint(x: f.minX, y: 0), to: CGPoint(x: f.maxX, y: 0))
        ctx.stroke(CGPath(rect: f.insetBy(dx: 1, dy: 1), transform: nil), white(1, 0.14), width: 1.2)
        let mat = f.insetBy(dx: 14, dy: 14)
        ctx.fill(CGPath(rect: mat, transform: nil), rgb(0xEEE7D7))
        ctx.stroke(CGPath(rect: mat.insetBy(dx: 1.5, dy: 1.5), transform: nil), white(0, 0.18), width: 3)
        let art = mat.insetBy(dx: 44, dy: 36)
        drawPrintArt(ctx, in: art)
        ctx.stroke(CGPath(rect: art, transform: nil), white(0, 0.3), width: 1)
    }

    /// A quiet woodblock-style landscape for the framed print.
    private func drawPrintArt(_ ctx: CGContext, in r: CGRect) {
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(makeGradient([(0, rgb(0x223D35)), (1, rgb(0x3A5C49))]),
                               start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        ctx.fill(.ellipse(CGRect(center: CGPoint(x: r.maxX - 72, y: r.minY + 52), radius: 22)), rgb(0xE6D9B8, 0.92))
        for (i, col) in [UInt32(0x3F6A50), 0x52805B, 0x6E9869].enumerated() {
            let p = CGMutablePath()
            let fi = CGFloat(i)
            let base = r.minY + r.height * (0.40 + 0.17 * fi)
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            var x = r.minX
            while x <= r.maxX + 4 {
                p.addLine(to: CGPoint(x: x, y: base + 12 * sin(x * 0.021 + fi * 1.9) + 6 * sin(x * 0.063 + fi)))
                x += 4
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
            ctx.fill(p, rgb(col))
        }
        var rng = SplitMix64(seed: 5)
        for _ in 0..<18 {
            let c = CGPoint(x: .random(in: r.minX...r.maxX, using: &rng), y: .random(in: (r.maxY - 40)...(r.maxY - 6), using: &rng))
            ctx.fill(.ellipse(CGRect(center: c, radius: .random(in: 1.6...3, using: &rng))), rgb(0xF1E9D6, 0.9))
        }
        ctx.restoreGState()
    }

    private func deskTexture(unit: CGFloat) -> CGImage {
        let h = Double(1040 - G.deskTop)
        let top = Double(G.deskTop)
        return Texture.wood(width: Int(1600 * unit * 0.6), height: Int(CGFloat(h) * unit * 0.6), style: .mahogany) { nx, ny in
            // Perspective: equal steps in depth bunch up toward the back edge.
            let y = top + ny * h
            let depth = 705 / (y + 160)
            let x = (nx - 0.5) * 1600 / 700 * depth
            return (x * 1.1, depth * 3)
        }
    }

    private func drawDesk(_ ctx: CGContext, texture: CGImage) {
        let desk = CGRect(x: 0, y: G.deskTop, width: 1600, height: 1040 - G.deskTop)
        Draw.upright(ctx, texture, in: desk)
        ctx.saveGState()
        ctx.clip(to: desk)
        ctx.drawLinearGradient(makeGradient([(0, white(0, 0.5)), (0.07, white(0, 0.14)), (0.4, white(0, 0)), (1, white(0, 0.2))]),
                               start: CGPoint(x: 0, y: desk.minY), end: CGPoint(x: 0, y: desk.maxY), options: [])
        if !night {
            ctx.drawRadialGradient(makeGradient([(0, rgb(0xFFE2B0, 0.16)), (1, rgb(0xFFE2B0, 0))]),
                                   startCenter: CGPoint(x: 260, y: 650), startRadius: 0,
                                   endCenter: CGPoint(x: 260, y: 650), endRadius: 520, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: Lamp

    private func lampDome() -> CGPath {
        let cx = G.lampX
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx - 98, y: 512))
        p.addCurve(to: CGPoint(x: cx, y: 268), control1: CGPoint(x: cx - 104, y: 382), control2: CGPoint(x: cx - 74, y: 268))
        p.addCurve(to: CGPoint(x: cx + 98, y: 512), control1: CGPoint(x: cx + 74, y: 268), control2: CGPoint(x: cx + 104, y: 382))
        p.addQuadCurve(to: CGPoint(x: cx - 98, y: 512), control: CGPoint(x: cx, y: 532))
        p.closeSubpath()
        return p
    }

    private func drawRibs(_ ctx: CGContext, light: CGColor, dark: CGColor) {
        let cx = G.lampX
        ctx.saveGState()
        ctx.addPath(lampDome())
        ctx.clip()
        for i in -9...9 {
            let t = CGFloat(i) / 9.5
            let rib = CGMutablePath()
            rib.move(to: CGPoint(x: cx + t * 30, y: 268))
            rib.addCurve(to: CGPoint(x: cx + t * 100, y: 530),
                         control1: CGPoint(x: cx + t * 90, y: 300), control2: CGPoint(x: cx + t * 106, y: 420))
            ctx.stroke(rib, light, width: 3)
            var shift = CGAffineTransform(translationX: 3.4, y: 0)
            ctx.stroke(rib.copy(using: &shift)!, dark, width: 1.3)
        }
        ctx.restoreGState()
    }

    private func drawLamp(_ ctx: CGContext, unit: CGFloat) {
        let cx = G.lampX
        let dome = lampDome()
        if !night {
            Draw.castShadow(ctx, dome, dx: 46, dy: 18, blur: 30, color: white(0, 0.2), unit: unit)
        }
        let cord = CGMutablePath()
        cord.move(to: CGPoint(x: cx + 40, y: 606))
        cord.addCurve(to: CGPoint(x: 1640, y: 588), control1: CGPoint(x: cx + 110, y: 622), control2: CGPoint(x: 1560, y: 572))
        ctx.stroke(cord, rgb(0x1C1916), width: 3.5)

        let brass = makeGradient([(0, rgb(0x6E5330)), (0.35, rgb(0xE6CB8E)), (0.6, rgb(0xA5834C)), (1, rgb(0x5A4224))])
        let foot = CGRect(center: CGPoint(x: cx, y: 598), rx: 60, ry: 15)
        Draw.castShadow(ctx, .ellipse(foot.offsetBy(dx: 0, dy: 8)), dx: night ? -10 : 16, dy: 6, blur: 14,
                        color: white(0, 0.5), unit: unit)
        ctx.fill(.ellipse(foot.offsetBy(dx: 0, dy: 8)), rgb(0x5E4524))
        ctx.fill(CGPath(rect: CGRect(x: foot.minX, y: foot.midY, width: foot.width, height: 8), transform: nil),
                 linear: brass, from: CGPoint(x: foot.minX, y: 0), to: CGPoint(x: foot.maxX, y: 0))
        ctx.fill(.ellipse(foot), linear: makeGradient([(0, rgb(0xE0C383)), (1, rgb(0x8C6B3A))]),
                 from: CGPoint(x: cx, y: foot.minY), to: CGPoint(x: cx, y: foot.maxY))
        let stem = CGRect(x: cx - 15, y: 510, width: 30, height: 88)
        ctx.fill(CGPath(rect: stem, transform: nil), linear: brass,
                 from: CGPoint(x: stem.minX, y: 0), to: CGPoint(x: stem.maxX, y: 0))

        ctx.fill(dome, linear: makeGradient([(0, rgb(0x8A806E)), (1, rgb(0xB9AD93))]),
                 from: CGPoint(x: cx, y: 268), to: CGPoint(x: cx, y: 520))
        drawRibs(ctx, light: white(1, 0.16), dark: white(0, 0.10))
        ctx.saveGState()
        ctx.addPath(dome)
        ctx.clip()
        ctx.drawLinearGradient(makeGradient([(0, white(1, 0.24)), (0.35, white(1, 0)), (0.75, white(0, 0)), (1, white(0, 0.2))]),
                               start: CGPoint(x: cx - 100, y: 0), end: CGPoint(x: cx + 100, y: 0), options: [])
        ctx.restoreGState()
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: cx - 98, y: 512))
        rim.addQuadCurve(to: CGPoint(x: cx + 98, y: 512), control: CGPoint(x: cx, y: 532))
        ctx.stroke(rim, white(1, 0.35), width: 2)
    }

    private func drawLitShade(_ ctx: CGContext) {
        let cx = G.lampX
        let dome = lampDome()
        ctx.fill(dome, radial: makeGradient([(0, rgb(0xFFF7E2)), (0.3, rgb(0xFFD794)), (0.7, rgb(0xEDA357)), (1, rgb(0xB06A2C))]),
                 center: G.bulb, radius: 175)
        drawRibs(ctx, light: rgb(0xFFF1D0, 0.35), dark: rgb(0x7A4518, 0.22))
        ctx.saveGState()
        ctx.addPath(dome)
        ctx.clip()
        ctx.drawLinearGradient(makeGradient([(0, white(0, 0.28)), (0.45, white(0, 0))]),
                               start: CGPoint(x: 0, y: 268), end: CGPoint(x: 0, y: 520), options: [])
        ctx.restoreGState()
        // Bulb filament glow seen through the glass.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30 * canvas.unit, color: rgb(0xFFF4D6))
        ctx.fill(.ellipse(CGRect(center: G.bulb, rx: 24, ry: 32)), rgb(0xFFFBF0, 0.95))
        ctx.restoreGState()
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: cx - 98, y: 512))
        rim.addQuadCurve(to: CGPoint(x: cx + 98, y: 512), control: CGPoint(x: cx, y: 532))
        ctx.stroke(rim, rgb(0xFFE7B5, 0.8), width: 2.5)
    }

    // MARK: Album stand

    private func drawStandBack(_ ctx: CGContext, unit: CGFloat) {
        let top = CGPath.polygon([CGPoint(x: 104, y: 706), CGPoint(x: 516, y: 706),
                                  CGPoint(x: 524, y: 742), CGPoint(x: 96, y: 742)])
        let body = CGPath.polygon([CGPoint(x: 104, y: 706), CGPoint(x: 516, y: 706), CGPoint(x: 524, y: 742),
                                   CGPoint(x: 524, y: 790), CGPoint(x: 96, y: 790), CGPoint(x: 96, y: 742)])
        Draw.castShadow(ctx, body, dx: night ? -14 : 18, dy: 10, blur: 16, color: white(0, 0.5), unit: unit)
        ctx.saveGState()
        ctx.addPath(top)
        ctx.clip()
        Draw.upright(ctx, walnut, in: top.boundingBox)
        ctx.fill(top, white(1, 0.2))
        ctx.restoreGState()
        ctx.line(CGPoint(x: 101, y: 726), CGPoint(x: 519, y: 726), white(0, 0.65), width: 4)
    }

    private func drawStandFront(_ ctx: CGContext) {
        let lip = CGPath.polygon([CGPoint(x: 100, y: 728.5), CGPoint(x: 520, y: 728.5),
                                  CGPoint(x: 524, y: 742), CGPoint(x: 96, y: 742)])
        ctx.saveGState()
        ctx.addPath(lip)
        ctx.clip()
        Draw.upright(ctx, walnut, in: lip.boundingBox.insetBy(dx: 0, dy: -20))
        ctx.fill(lip, white(1, 0.26))
        ctx.restoreGState()
        let face = CGRect(x: 96, y: 742, width: 428, height: 48)
        Draw.upright(ctx, walnut, in: face)
        ctx.fill(CGPath(rect: face, transform: nil), linear: makeGradient([(0, white(1, 0.05)), (1, white(0, 0.38))]),
                 from: CGPoint(x: 0, y: face.minY), to: CGPoint(x: 0, y: face.maxY))
        ctx.line(CGPoint(x: 96, y: 742), CGPoint(x: 524, y: 742), white(1, 0.35), width: 1.2)
    }

    // MARK: Prints & turntable

    private func drawSheets(_ ctx: CGContext, unit: CGFloat) {
        let sheets: [(CGPoint, CGFloat, CGFloat, UInt32)] = [
            (CGPoint(x: 1348, y: 726), 392, 0.09, 0xDDD9D1),
            (CGPoint(x: 1334, y: 720), 386, -0.05, 0xE9E6E0),
            (CGPoint(x: 1352, y: 713), 380, 0.02, 0xF4F2EE),
        ]
        for (i, s) in sheets.enumerated() {
            let path = CGPath.flatSquare(center: s.0, side: s.1, angle: s.2, tilt: G.tilt)
            if i == 0 {
                Draw.castShadow(ctx, path, dx: night ? -10 : 14, dy: 6, blur: 10, color: white(0, 0.45), unit: unit)
            }
            ctx.fill(path, rgb(s.3))
            ctx.stroke(path, white(0, 0.12), width: 1)
        }
    }

    private func drawTurntable(_ ctx: CGContext, unit: CGFloat) {
        let t = G.plinthTop, f = G.plinthFront
        let silhouette = CGPath.polygon([t[0], t[1], CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)])
        Draw.castShadow(ctx, silhouette, dx: night ? -20 : 22, dy: 12, blur: 22, color: white(0, 0.5), unit: unit)
        Draw.castShadow(ctx, CGPath(rect: CGRect(x: f.minX + 6, y: f.maxY - 8, width: f.width - 12, height: 8), transform: nil),
                        dx: 0, dy: 3, blur: 5, color: white(0, 0.75), unit: unit)

        // Front face: cream band over a walnut base.
        ctx.saveGState()
        ctx.addPath(.rounded(f, 8))
        ctx.clip()
        ctx.fill(CGPath(rect: CGRect(x: f.minX, y: f.minY, width: f.width, height: 50), transform: nil),
                 linear: makeGradient([(0, rgb(0xE6E0D3)), (1, rgb(0xCDC5B5))]),
                 from: CGPoint(x: 0, y: f.minY), to: CGPoint(x: 0, y: f.minY + 50))
        let base = CGRect(x: f.minX, y: f.minY + 50, width: f.width, height: f.height - 50)
        Draw.upright(ctx, walnut, in: base)
        ctx.drawLinearGradient(makeGradient([(0, white(1, 0.06)), (1, white(0, 0.4))]),
                               start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
        ctx.line(CGPoint(x: f.minX, y: base.minY), CGPoint(x: f.maxX, y: base.minY), white(0, 0.35), width: 1.2)
        ctx.restoreGState()
        Draw.text("PLATTER", at: CGPoint(x: f.minX + 34, y: base.minY + 30), size: 11, weight: .bold,
                  color: white(0, 0.42), kern: 3.4)

        // Top face.
        let top = CGPath.polygon(t)
        ctx.fill(top, linear: makeGradient([(0, rgb(0xD3CCBD)), (1, rgb(0xF0EBE1))]),
                 from: CGPoint(x: 0, y: t[0].y), to: CGPoint(x: 0, y: t[2].y))
        ctx.line(t[3], t[2], white(1, 0.8), width: 1.6)
        ctx.stroke(top, white(0, 0.12), width: 1)

        // Platter: chrome edge with a mat on top.
        let c = G.platterCenter, r = G.platterRadius, ry = r * G.tilt
        let chrome = makeGradient([(0, white(0.42)), (0.22, white(0.93)), (0.5, white(0.6)), (0.78, white(0.96)), (1, white(0.4))])
        let lower = CGRect(center: CGPoint(x: c.x, y: c.y + 10), rx: r, ry: ry)
        Draw.castShadow(ctx, .ellipse(lower), dx: 0, dy: 4, blur: 8, color: white(0, 0.5), unit: unit)
        ctx.fill(.ellipse(lower), linear: chrome, from: CGPoint(x: c.x - r, y: 0), to: CGPoint(x: c.x + r, y: 0))
        ctx.fill(CGPath(rect: CGRect(x: c.x - r, y: c.y, width: 2 * r, height: 10), transform: nil),
                 linear: chrome, from: CGPoint(x: c.x - r, y: 0), to: CGPoint(x: c.x + r, y: 0))
        ctx.fill(.ellipse(CGRect(center: c, rx: r, ry: ry)), linear: chrome,
                 from: CGPoint(x: c.x - r, y: 0), to: CGPoint(x: c.x + r, y: 0))
        ctx.fill(.ellipse(CGRect(center: c, rx: r - 6, ry: (r - 6) * G.tilt)), rgb(0x1B1B1B))

        // Speed knob and power light on the front band.
        let knob = CGPoint(x: 1019, y: 680)
        Draw.castShadow(ctx, .ellipse(CGRect(center: knob, radius: 12)), dx: 2, dy: 3, blur: 4, color: white(0, 0.45), unit: unit)
        ctx.fill(.ellipse(CGRect(center: knob, radius: 12)),
                 radial: makeGradient([(0, rgb(0xF2DA98)), (0.6, rgb(0xC09A4E)), (1, rgb(0x7E5E2A))]),
                 center: CGPoint(x: knob.x - 3, y: knob.y - 4), radius: 15)
        let led = CGPoint(x: 976, y: 682)
        ctx.fill(.ellipse(CGRect(center: led, radius: 3.5)), rgb(0x262626))
        ctx.stroke(.ellipse(CGRect(center: led, radius: 3.5)), white(1, 0.4), width: 0.8)
    }

    private func drawTonearm(_ ctx: CGContext) {
        let unit = canvas.unit
        let p = G.pivot, s = G.stylus
        let post = CGRect(x: p.x - 16, y: p.y - 12, width: 32, height: 26)
        Draw.castShadow(ctx, .ellipse(CGRect(center: CGPoint(x: p.x, y: post.maxY), rx: 18, ry: 6)),
                        dx: night ? -8 : 10, dy: 2, blur: 5, color: white(0, 0.5), unit: unit)
        ctx.fill(CGPath(rect: post, transform: nil),
                 linear: makeGradient([(0, white(0.05)), (0.4, white(0.32)), (1, white(0.04))]),
                 from: CGPoint(x: post.minX, y: 0), to: CGPoint(x: post.maxX, y: 0))
        ctx.fill(.ellipse(CGRect(center: CGPoint(x: p.x, y: post.maxY), rx: 16, ry: 5)), white(0.06))
        ctx.fill(.ellipse(CGRect(center: CGPoint(x: p.x, y: post.minY), rx: 16, ry: 5)), white(0.3))

        // Counterweight reaching back.
        let cw0 = CGPoint(x: p.x + 3, y: p.y - 18), cw1 = CGPoint(x: p.x + 24, y: p.y - 64)
        ctx.line(cw0, CGPoint(x: p.x + 14, y: p.y - 42), white(0.7), width: 4, cap: .round)
        ctx.line(CGPoint(x: p.x + 14, y: p.y - 42), cw1, white(0.12), width: 16, cap: .round)
        ctx.line(CGPoint(x: p.x + 12, y: p.y - 44), CGPoint(x: cw1.x - 3, y: cw1.y + 2), white(0.55, 0.7), width: 3, cap: .round)
        ctx.fill(.ellipse(CGRect(center: CGPoint(x: p.x, y: p.y - 16), rx: 12, ry: 7)),
                 radial: makeGradient([(0, white(0.97)), (1, white(0.5))]), center: CGPoint(x: p.x - 3, y: p.y - 19), radius: 13)

        // Arm tube, with its shadow on the platter.
        let arm = CGMutablePath()
        arm.move(to: CGPoint(x: p.x - 2, y: p.y - 16))
        arm.addCurve(to: CGPoint(x: s.x + 20, y: s.y - 12),
                     control1: CGPoint(x: p.x - 70, y: p.y + 4), control2: CGPoint(x: s.x + 72, y: s.y - 28))
        ctx.setLineCap(.round)
        ctx.saveGState()
        Draw.shadow(ctx, dx: night ? -6 : 6, dy: 12, blur: 6, color: white(0, 0.45), unit: unit)
        ctx.stroke(arm, white(0.7), width: 5.5)
        ctx.restoreGState()
        var up = CGAffineTransform(translationX: 0, y: -1.4)
        ctx.stroke(arm.copy(using: &up)!, white(1, 0.85), width: 1.6)

        // Headshell and cartridge.
        ctx.saveGState()
        ctx.translateBy(x: s.x + 8, y: s.y - 7)
        ctx.rotate(by: -0.36)
        ctx.fill(.rounded(CGRect(x: -18, y: -6, width: 32, height: 12), 2.5), white(0.13))
        ctx.fill(CGPath(rect: CGRect(x: -15, y: 2, width: 14, height: 7), transform: nil), rgb(0xC9A04F))
        ctx.line(CGPoint(x: 12, y: -4), CGPoint(x: 18, y: -14), white(0.82), width: 2, cap: .round)
        ctx.restoreGState()
    }

    // MARK: - Night lighting

    /// Darkness falling off around the lamp (and a little warm spill from the left).
    private func nightShade() -> CGImage {
        let w = 400, h = 260
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Double(x) + 0.5) / Double(w) * 1600, dy = (Double(y) + 0.5) / Double(h) * 1040
                let lamp = 0.74 * exp(-pow(hypot(dx - 1447, (dy - 440) * 1.15) / 560, 2))
                let left = 0.40 * exp(-pow((dx + 40) / 380, 2)) * exp(-pow((dy - 380) / 420, 2))
                let art = 0.16 * exp(-pow(hypot(dx - 986, dy - 110) / 240, 2))
                let a = min(0.80, max(0.08, 0.80 - lamp - left - art))
                let i = (y * w + x) * 4
                buf[i] = UInt8(22 * a)
                buf[i + 1] = UInt8(11 * a)
                buf[i + 2] = UInt8(6 * a)
                buf[i + 3] = UInt8(255 * a)
            }
        }
        return Texture.makeImage(buf, width: w, height: h)
    }

    /// Warm haze around the bulb and the pool of light it throws on the desk.
    private func lampHalo() -> CGImage {
        let w = 400, h = 260
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Double(x) + 0.5) / Double(w) * 1600, dy = (Double(y) + 0.5) / Double(h) * 1040
                let halo = 0.34 * exp(-pow(hypot(dx - 1447, dy - 420) / 300, 2))
                let core = 0.30 * exp(-pow(hypot(dx - 1447, dy - 430) / 110, 2))
                let pool = 0.22 * exp(-(pow((dx - 1430) / 300, 2) + pow((dy - 612) / 70, 2)))
                let left = 0.10 * exp(-pow((dx + 20) / 220, 2)) * exp(-pow((dy - 360) / 300, 2))
                let a = min(0.9, halo + core + pool + left)
                let i = (y * w + x) * 4
                buf[i] = UInt8(255 * a)
                buf[i + 1] = UInt8(178 * a)
                buf[i + 2] = UInt8(98 * a)
                buf[i + 3] = UInt8(255 * a)
            }
        }
        return Texture.makeImage(buf, width: w, height: h)
    }
}
