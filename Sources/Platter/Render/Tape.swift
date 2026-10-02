import AppKit

/// Cassette parts shared by the tape scenes. Sizes are design units; `unit` is pixels per unit.
enum Tape {
    /// Label sticker: the cover with a handwritten title strip, cut around the tape window.
    /// Drawn in design coordinates into an image covering `label`. `s` scales the strip and type.
    static func label(_ l: CGRect, window: CGRect, art: CGImage?, text: String, s: CGFloat, unit: CGFloat) -> CGImage {
        Draw.image(size: l.size, ppu: unit) { ctx in
            ctx.translateBy(x: -l.minX, y: -l.minY)
            ctx.saveGState()
            ctx.addPath(.rounded(l, 6 * s))
            ctx.clip()
            if let art {
                Draw.aspectFill(ctx, art, in: l)
            } else {
                ctx.fill(CGPath(rect: l, transform: nil), rgb(0xE9E2D2))
            }
            let strip = CGRect(x: l.minX, y: l.minY, width: l.width, height: 36 * s)
            ctx.fill(CGPath(rect: strip, transform: nil), rgb(0xF5F1E8))
            ctx.fill(CGPath(rect: CGRect(x: l.minX, y: strip.maxY, width: l.width, height: 3 * s), transform: nil), rgb(0xD9472F))
            Draw.text("A", at: CGPoint(x: l.minX + 12 * s, y: l.minY + 4 * s), size: 24 * s, weight: .black, color: rgb(0x2A2A2A))
            NSAttributedString(string: text.isEmpty ? "PLATTER MIXTAPE" : text, attributes: [
                .font: NSFont(name: "Marker Felt", size: 19 * s) ?? NSFont.systemFont(ofSize: 18 * s, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 0.9),
            ]).draw(with: CGRect(x: l.minX + 46 * s, y: l.minY + 7 * s, width: l.width - 60 * s, height: 26 * s),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            let tw = window.insetBy(dx: -6 * s, dy: -6 * s)
            ctx.setBlendMode(.clear)
            ctx.fill(.rounded(tw, tw.height / 2), white(0))
            ctx.setBlendMode(.normal)
            ctx.stroke(.rounded(tw, tw.height / 2), white(0, 0.5), width: 2 * s)
            ctx.restoreGState()
            ctx.stroke(.rounded(l.insetBy(dx: 0.5, dy: 0.5), 6 * s), white(0, 0.25), width: 1)
        }
    }

    /// Wound tape: a brown disc with faint winding rings. Scaled by its layer as tape moves.
    static func pack(unit: CGFloat) -> CGImage {
        let d: CGFloat = 140
        return Draw.image(size: CGSize(width: d, height: d), ppu: unit) { ctx in
            let c = CGPoint(x: d / 2, y: d / 2)
            ctx.fill(.ellipse(CGRect(center: c, radius: d / 2)), radial: makeGradient([(0, rgb(0x4A2E1C)), (1, rgb(0x2A190F))]),
                     center: c, radius: d / 2)
            var rng = SplitMix64(seed: 17)
            var r: CGFloat = 8
            while r < d / 2 {
                ctx.stroke(.ellipse(CGRect(center: c, radius: r)), white(1, .random(in: 0.02...0.07, using: &rng)), width: 0.6)
                r += .random(in: 1.2...2.6, using: &rng)
            }
            ctx.stroke(.ellipse(CGRect(center: c, radius: d / 2 - 0.8)), white(1, 0.12), width: 1.2)
        }
    }

    /// White spool hub with drive teeth.
    static func hub(radius r: CGFloat, unit: CGFloat) -> CGImage {
        let d = r * 2
        return Draw.image(size: CGSize(width: d, height: d), ppu: unit) { ctx in
            let c = CGPoint(x: r, y: r)
            ctx.fill(.ellipse(CGRect(center: c, radius: r)), white(0.93))
            ctx.stroke(.ellipse(CGRect(center: c, radius: r - 0.6)), white(0, 0.25), width: 1)
            ctx.fill(.ellipse(CGRect(center: c, radius: r * 0.52)), rgb(0x0C0D0F))
            for i in 0..<6 {
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: CGFloat(i) / 6 * 2 * .pi)
                ctx.fill(CGPath(rect: CGRect(x: r * 0.36, y: -r * 0.1, width: r * 0.2, height: r * 0.2), transform: nil), white(0.93))
                ctx.restoreGState()
            }
            for i in 0..<3 {
                let a = CGFloat(i) / 3 * 2 * .pi + 0.5
                ctx.fill(.ellipse(CGRect(center: CGPoint(x: c.x + cos(a) * r * 0.76, y: c.y + sin(a) * r * 0.76), radius: r * 0.12)),
                         white(0, 0.3))
            }
        }
    }

    /// Spools seen through a cassette's window: returns the clipping container plus pack and hub layers.
    static func reels(in window: CGRect, hubs centers: [CGPoint], hubRadius: CGFloat, canvas: Canvas)
        -> (container: CALayer, packs: [CALayer], hubs: [CALayer]) {
        let k = canvas.k
        let container = CALayer()
        container.frame = canvas.rect(window)
        container.masksToBounds = true
        container.cornerRadius = window.height / 2 * k
        let packImage = pack(unit: canvas.unit)
        let hubImage = hub(radius: hubRadius, unit: canvas.unit)
        var packs: [CALayer] = [], hubs: [CALayer] = []
        for c in centers {
            let local = CGPoint(x: (c.x - window.minX) * k, y: (window.maxY - c.y) * k)
            let pack = CALayer()
            pack.contents = packImage
            pack.position = local
            container.addSublayer(pack)
            packs.append(pack)
            let h = CALayer()
            h.bounds = CGRect(x: 0, y: 0, width: hubRadius * 2 * k, height: hubRadius * 2 * k)
            h.position = local
            h.contents = hubImage
            container.addSublayer(h)
            hubs.append(h)
        }
        return (container, packs, hubs)
    }

    /// Resizes the tape packs: tape leaves the left spool and builds up on the right one.
    static func wind(_ packs: [CALayer], progress: Double, range: ClosedRange<CGFloat>, k: CGFloat, animated: Bool) {
        let p = CGFloat(progress), lo = range.lowerBound, hi = range.upperBound
        let radii = [hi - (hi - lo) * p, lo + (hi - lo) * p]
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (pack, r) in zip(packs, radii) {
            pack.bounds = CGRect(x: 0, y: 0, width: 2 * r * k, height: 2 * r * k)
        }
        CATransaction.commit()
    }
}
