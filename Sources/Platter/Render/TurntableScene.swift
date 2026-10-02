import AppKit
import QuartzCore

/// Top-down view: a turntable and the album sleeve on a sunlit wooden table.
final class TurntableScene: DesktopScene {
    private enum G {
        static let plinth = CGRect(x: 677, y: 204, width: 740, height: 664)
        static let recordCenter = CGPoint(x: 974, y: 527)
        static let recordRadius: CGFloat = 270
        static let platterRadius: CGFloat = 288
        static let pivot = CGPoint(x: 1309, y: 344)
        static let armLength: CGFloat = 292
        static let restAngle: CGFloat = 0.12
        static let knob = CGPoint(x: 1316, y: 714)
        static let sleeve = CGRect(x: 120, y: 304, width: 540, height: 540)
        static let sleeveAngle: CGFloat = 0.045
        static let badge = CGRect(x: 708, y: 826, width: 118, height: 24)
        static let startButton = CGPoint(x: 730, y: 258)
        // Tonearm image layout: pivot sits at (armPivotX, armPivotY) inside the image, the arm points down.
        static let armWidth: CGFloat = 120
        static let armPivotY: CGFloat = 84
        static var armHeight: CGFloat { armPivotY + armLength + 34 }
    }

    private let sleeve = CALayer()
    private let disc = CALayer()
    private let arm = CALayer()
    private var startButton = CALayer()
    private lazy var spinner = Spinner(layer: disc)

    override func build() {
        _ = addImageLayer(background(), frame: CGRect(origin: .zero, size: Canvas.design))

        let buttonRect = CGRect(center: G.startButton, radius: 20)
        startButton = addImageLayer(patch(buttonRect) { drawStartButton($0) }, frame: buttonRect)

        let k = canvas.k
        sleeve.bounds = CGRect(x: 0, y: 0, width: G.sleeve.width * k, height: G.sleeve.height * k)
        sleeve.position = canvas.point(G.sleeve.center)
        sleeve.transform = CATransform3DMakeRotation(G.sleeveAngle, 0, 0, 1)
        applyShadow(sleeve, dx: -10, dy: 16, blur: 22, opacity: 0.55)
        root.addSublayer(sleeve)

        let recordRect = CGRect(center: G.recordCenter, radius: G.recordRadius)
        disc.frame = canvas.rect(recordRect)
        root.addSublayer(disc)
        _ = addImageLayer(Vinyl.sheen(diameter: G.recordRadius * 2, unit: canvas.unit), frame: recordRect)

        arm.bounds = CGRect(x: 0, y: 0, width: G.armWidth * k, height: G.armHeight * k)
        arm.anchorPoint = CGPoint(x: 0.5, y: 1 - G.armPivotY / G.armHeight)
        arm.position = canvas.point(G.pivot)
        arm.contents = tonearm()
        arm.shadowColor = .black
        arm.shadowOpacity = 0.5
        arm.shadowRadius = 5 * k
        arm.shadowOffset = CGSize(width: -7 * k, height: -9 * k)
        root.addSublayer(arm)

        _ = addImageLayer(windowLight(), frame: CGRect(origin: .zero, size: Canvas.design))
    }

    override func artworkDidChange(animated: Bool) {
        setContents(sleeve, Vinyl.sleeve(side: G.sleeve.width, art: artwork, unit: canvas.unit), animated: animated)
        setContents(disc, Vinyl.disc(diameter: G.recordRadius * 2, art: artwork, unit: canvas.unit), animated: animated)
    }

    override func playbackDidChange(animated: Bool) {
        spinner.set(spinning: isPlaying)
        moveArm(duration: animated ? 1.4 : 0, timing: .easeInEaseOut)
        if animated { squeeze(startButton) }
    }

    override func progressDidChange(animated: Bool) {
        guard isPlaying else { return }
        moveArm(duration: animated ? Self.progressTick : 0, timing: .linear)
    }

    private func moveArm(duration: CFTimeInterval, timing: CAMediaTimingFunctionName) {
        // The stylus creeps from the outer groove toward the label as the track plays.
        let groove = G.recordRadius * (0.93 - 0.52 * CGFloat(progress))
        let angle = isPlaying ? armAngle(groove: groove) : G.restAngle
        CATransaction.begin()
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: timing))
        arm.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
    }

    /// Rotation that puts the stylus on the groove of radius `groove`.
    private func armAngle(groove rho: CGFloat) -> CGFloat {
        let p = G.pivot, c = G.recordCenter, l = G.armLength
        let dx = c.x - p.x, dy = c.y - p.y, d = hypot(dx, dy)
        let a = (l * l - rho * rho + d * d) / (2 * d)
        let h = sqrt(max(0, l * l - a * a))
        let bx = p.x + a * dx / d, by = p.y + a * dy / d
        let t1 = CGPoint(x: bx - h * dy / d, y: by + h * dx / d)
        let t2 = CGPoint(x: bx + h * dy / d, y: by - h * dx / d)
        let t = t1.y > t2.y ? t1 : t2
        return atan2(t.x - p.x, t.y - p.y)
    }

    // MARK: - Artwork

    private func background() -> CGImage {
        let unit = canvas.unit
        let woodScale = 0.5
        let wood = Texture.wood(
            width: Int(Canvas.design.width * unit * woodScale), height: Int(Canvas.design.height * unit * woodScale),
            style: WoodStyle(dark: WoodStyle.hex(0x6E300E), mid: WoodStyle.hex(0xA6511C),
                             light: WoodStyle.hex(0xCB7A38), rings: 14, streaks: 70, seed: 4)
        ) { nx, ny in (nx * 1.6, ny * 1.04) }

        return Draw.image(size: canvas.size, ppu: canvas.scale) { ctx in
            canvas.enterDesignSpace(ctx)
            Draw.upright(ctx, wood, in: CGRect(origin: .zero, size: Canvas.design))
            drawPlinth(ctx, unit: unit)
        }
    }

    private func drawPlinth(_ ctx: CGContext, unit: CGFloat) {
        let body = CGPath.rounded(G.plinth, 22)

        // Cast shadow + contact shadow.
        Draw.castShadow(ctx, body, dx: -16, dy: 22, blur: 46, color: white(0, 0.55), unit: unit)
        Draw.castShadow(ctx, body, dx: -3, dy: 4, blur: 6, color: white(0, 0.5), unit: unit)

        // Painted top with brushed texture.
        ctx.fill(body, linear: makeGradient([(0, rgb(0xE0DACD)), (0.55, rgb(0xD2CABB)), (1, rgb(0xBDB4A3))]),
                 from: G.plinth.origin, to: CGPoint(x: G.plinth.maxX, y: G.plinth.maxY))
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let brushed = Texture.brushed(strength: 0.10)
        let tile = CGFloat(brushed.width) / unit
        ctx.draw(brushed, in: CGRect(x: 0, y: 0, width: tile, height: tile), byTiling: true)
        ctx.restoreGState()
        ctx.stroke(.rounded(G.plinth.insetBy(dx: 1.5, dy: 1.5), 21), white(1, 0.45), width: 1.6)
        ctx.stroke(.rounded(G.plinth, 22), white(0, 0.35), width: 1.2)

        // Platter well and chrome rim.
        let c = G.recordCenter
        ctx.saveGState()
        Draw.shadow(ctx, dx: 0, dy: 2, blur: 6, color: white(1, 0.6), unit: unit)
        ctx.fill(.ellipse(CGRect(center: c, radius: G.platterRadius + 6)), rgb(0x8E8778))
        ctx.restoreGState()
        ctx.fill(.ellipse(CGRect(center: c, radius: G.platterRadius + 5)), rgb(0x2A2A2B))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(center: c, radius: G.platterRadius))
        ctx.addEllipse(in: CGRect(center: c, radius: G.platterRadius - 9))
        ctx.clip(using: .evenOdd)
        ctx.drawConicGradient(makeGradient([
            (0, white(0.55)), (0.12, white(0.95)), (0.25, white(0.6)), (0.4, white(0.4)),
            (0.55, white(0.9)), (0.7, white(0.5)), (0.85, white(0.75)), (1, white(0.55)),
        ]), center: c, angle: 0)
        ctx.restoreGState()
        ctx.fill(.ellipse(CGRect(center: c, radius: G.platterRadius - 9)), rgb(0x1A1A1B))

        // Seat for the start button.
        ctx.fill(.ellipse(CGRect(center: G.startButton, radius: 19)), white(0, 0.12))

        // Tonearm base, rest post and anti-skate dial.
        let p = G.pivot
        Draw.castShadow(ctx, .ellipse(CGRect(center: p, radius: 44)), dx: -5, dy: 7, blur: 10, color: white(0, 0.45), unit: unit)
        ctx.fill(.ellipse(CGRect(center: p, radius: 44)),
                 radial: makeGradient([(0, rgb(0xE9E6E0)), (0.7, rgb(0xBDB8AE)), (1, rgb(0x8F897D))]),
                 center: CGPoint(x: p.x + 10, y: p.y - 12), radius: 52)
        ctx.stroke(.ellipse(CGRect(center: p, radius: 44)), white(0, 0.3), width: 1)
        ctx.stroke(.ellipse(CGRect(center: p, radius: 30)), white(0, 0.25), width: 1.4)

        let rest = CGPoint(x: p.x + G.armLength * 0.6 * sin(G.restAngle), y: p.y + G.armLength * 0.6 * cos(G.restAngle))
        Draw.castShadow(ctx, .ellipse(CGRect(center: rest, radius: 10)), dx: -3, dy: 4, blur: 5, color: white(0, 0.5), unit: unit)
        ctx.fill(.ellipse(CGRect(center: rest, radius: 10)), radial: makeGradient([(0, white(0.35)), (1, white(0.12))]),
                 center: CGPoint(x: rest.x + 3, y: rest.y - 3), radius: 12)

        let dial = CGPoint(x: p.x + 62, y: p.y - 36)
        ctx.fill(.ellipse(CGRect(center: dial, radius: 11)), radial: makeGradient([(0, white(0.92)), (1, white(0.6))]),
                 center: CGPoint(x: dial.x + 2, y: dial.y - 3), radius: 13)
        ctx.stroke(.ellipse(CGRect(center: dial, radius: 11)), white(0, 0.3), width: 1)

        // Pitch knob.
        let kn = G.knob
        Draw.castShadow(ctx, .ellipse(CGRect(center: kn, radius: 36)), dx: -5, dy: 8, blur: 10, color: white(0, 0.5), unit: unit)
        ctx.fill(.ellipse(CGRect(center: kn, radius: 36)),
                 radial: makeGradient([(0, rgb(0x9C7A55)), (0.6, rgb(0x6E5236)), (1, rgb(0x4A3522))]),
                 center: CGPoint(x: kn.x + 10, y: kn.y - 12), radius: 44)
        for i in 0..<48 {
            let a = CGFloat(i) / 48 * 2 * .pi
            ctx.line(CGPoint(x: kn.x + cos(a) * 32, y: kn.y + sin(a) * 32),
                     CGPoint(x: kn.x + cos(a) * 36, y: kn.y + sin(a) * 36), white(0, 0.22), width: 1)
        }
        ctx.stroke(.ellipse(CGRect(center: kn, radius: 24)), white(1, 0.10), width: 1.2)
        ctx.fill(.ellipse(CGRect(center: CGPoint(x: kn.x + 14, y: kn.y - 14), radius: 3)), white(0.9, 0.8))

        // Maker's badge.
        ctx.fill(.rounded(G.badge, 4), rgb(0x2E2B28))
        ctx.stroke(.rounded(G.badge.insetBy(dx: 0.5, dy: 0.5), 4), white(1, 0.12), width: 1)
        Draw.text("PLATTER", at: CGPoint(x: G.badge.midX, y: G.badge.minY + 5.5), size: 10.5, weight: .semibold,
                  color: rgb(0xC9C2B4), kern: 3.2, centered: true)
    }

    private func drawStartButton(_ ctx: CGContext) {
        let b = G.startButton
        ctx.fill(.ellipse(CGRect(center: b, radius: 17)), radial: makeGradient([(0, rgb(0xD6CFC1)), (1, rgb(0xB7AE9D))]),
                 center: CGPoint(x: b.x - 4, y: b.y - 4), radius: 20)
        ctx.stroke(.ellipse(CGRect(center: b, radius: 17)), white(0, 0.18), width: 1)
        ctx.fill(.ellipse(CGRect(center: b, radius: 4)), rgb(0xB5442E, 0.8))
    }

    /// The tonearm, drawn pointing straight down from its pivot.
    private func tonearm() -> CGImage {
        Draw.image(size: CGSize(width: G.armWidth, height: G.armHeight), ppu: canvas.unit) { ctx in
            let x = G.armWidth / 2, py = G.armPivotY, l = G.armLength
            let chrome = makeGradient([(0, white(0.45)), (0.35, white(0.97)), (0.6, white(0.72)), (1, white(0.38))])

            // Counterweight on a short stub behind the pivot.
            ctx.fill(CGPath(rect: CGRect(x: x - 4, y: py - 52, width: 8, height: 52), transform: nil),
                     linear: chrome, from: CGPoint(x: x - 4, y: 0), to: CGPoint(x: x + 4, y: 0))
            let weight = CGRect(x: x - 18, y: py - 82, width: 36, height: 42)
            ctx.fill(.rounded(weight, 7), linear: makeGradient([(0, white(0.16)), (0.4, white(0.55)), (0.65, white(0.3)), (1, white(0.1))]),
                     from: CGPoint(x: weight.minX, y: 0), to: CGPoint(x: weight.maxX, y: 0))
            for i in 1..<6 {
                let y = weight.minY + CGFloat(i) * 7
                ctx.line(CGPoint(x: weight.minX + 2, y: y), CGPoint(x: weight.maxX - 2, y: y), white(0, 0.35), width: 1)
            }

            // Arm tube.
            let tube = CGRect(x: x - 4.5, y: py, width: 9, height: l - 50)
            ctx.fill(.rounded(tube, 4.5), linear: chrome, from: CGPoint(x: tube.minX, y: 0), to: CGPoint(x: tube.maxX, y: 0))

            // Headshell with cartridge and finger lift.
            let shell = CGRect(x: x - 14, y: py + l - 58, width: 28, height: 52)
            ctx.fill(.rounded(shell, 4), linear: chrome, from: CGPoint(x: shell.minX, y: 0), to: CGPoint(x: shell.maxX, y: 0))
            let cart = CGRect(x: x - 10, y: py + l - 34, width: 20, height: 30)
            ctx.fill(.rounded(cart, 3), rgb(0x141414))
            ctx.fill(CGPath(rect: CGRect(x: x - 10, y: py + l - 34, width: 20, height: 5), transform: nil), rgb(0xC9A04F))
            ctx.line(CGPoint(x: shell.maxX - 2, y: shell.minY + 10), CGPoint(x: shell.maxX + 16, y: shell.minY + 4),
                     white(0.85), width: 3, cap: .round)

            // Bearing cap.
            let p = CGPoint(x: x, y: py)
            ctx.fill(.ellipse(CGRect(center: p, radius: 21)),
                     radial: makeGradient([(0, white(0.98)), (0.6, white(0.72)), (1, white(0.42))]),
                     center: CGPoint(x: p.x + 5, y: p.y - 6), radius: 24)
            ctx.stroke(.ellipse(CGRect(center: p, radius: 13)), white(0, 0.35), width: 1.5)
            ctx.fill(.ellipse(CGRect(center: p, radius: 6)), white(0.85))
        }
    }

    /// Soft window-frame shadows and vignette laid over everything, record included.
    private func windowLight() -> CGImage {
        let img = Draw.image(size: Canvas.design, ppu: 0.25) { ctx in
            let slant: CGFloat = 0.62, width: CGFloat = 150, h: CGFloat = 1200
            for x0 in stride(from: CGFloat(-1000), through: 1900, by: 640) {
                ctx.fill(.polygon([
                    CGPoint(x: x0, y: -60), CGPoint(x: x0 + width, y: -60),
                    CGPoint(x: x0 + width + slant * h, y: h), CGPoint(x: x0 + slant * h, y: h),
                ]), white(0, 0.36))
            }
            ctx.drawRadialGradient(makeGradient([(0, white(0, 0)), (1, white(0, 0.38))]),
                                   startCenter: CGPoint(x: 820, y: 500), startRadius: 380,
                                   endCenter: CGPoint(x: 820, y: 500), endRadius: 1050,
                                   options: [.drawsAfterEndLocation])
        }
        return Draw.blur(img, sigma: 7)
    }
}
