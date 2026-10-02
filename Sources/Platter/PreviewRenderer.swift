import AppKit
import UniformTypeIdentifiers

/// Offscreen rendering for development: scene previews and the app icon.
enum PreviewRenderer {
    static func renderScenes(to dir: URL, size: CGSize = CGSize(width: 1470, height: 956), scale: CGFloat = 2) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let covers = SampleArt.all
        for kind in SceneKind.allCases {
          for mood in LightMood.allCases {
            let start = Date()
            let name = "\(kind.rawValue)-\(mood.rawValue)"
            let scene = DesktopScene.make(kind, mood: mood)
            scene.setArtwork(covers[0], history: Array(covers.dropFirst()), animated: false)
            scene.setTrackInfo(title: "Golden Hour", artist: "The Sample Covers", animated: false)
            scene.setPlaying(true, animated: false)
            scene.setProgress(0.3, animated: false)
            scene.layout(size: size, scale: scale)
            let image = snapshot(scene.root, size: size, scale: scale)
            write(image, to: dir.appendingPathComponent("\(name).png"))
            print("\(name): \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
          }
        }
        // Menu bar icon at 8×, black on a light bar and tinted white on a dark one.
        let glyph = StatusIcon.make()
        let strip = Draw.image(size: CGSize(width: 36, height: 18), ppu: 8) { ctx in
            ctx.fill(CGPath(rect: CGRect(x: 0, y: 0, width: 18, height: 18), transform: nil), white(0.93))
            ctx.fill(CGPath(rect: CGRect(x: 18, y: 0, width: 18, height: 18), transform: nil), white(0.15))
            glyph.draw(in: CGRect(x: 0, y: 0, width: 18, height: 18))
            let tinted = NSImage(size: glyph.size, flipped: false) { r in
                glyph.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: CGRect(x: 18, y: 0, width: 18, height: 18))
        }
        write(strip, to: dir.appendingPathComponent("status-icon.png"))
        // Wood swatches.
        for (name, style) in [("teak", WoodStyle.teak), ("mahogany", WoodStyle.mahogany), ("walnut", WoodStyle.walnut)] {
            let img = Texture.wood(width: 1200, height: 700, style: style) { ($0 * 1.6, $1 * 0.93) }
            write(img, to: dir.appendingPathComponent("wood-\(name).png"))
        }
    }

    static func renderIcon(to url: URL) {
        let s: CGFloat = 1024
        let image = Draw.image(size: CGSize(width: s, height: s), ppu: 1) { ctx in
            let body = CGRect(x: 100, y: 100, width: 824, height: 824)
            let shape = CGPath.rounded(body, 185)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: white(0, 0.35))
            ctx.fill(shape, rgb(0xA6511C))
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let wood = Texture.wood(width: 600, height: 600, style: .teak) { ($0 * 0.8, $1 * 0.8) }
            Draw.upright(ctx, wood, in: body)
            // Sleeve peeking out behind the record.
            let sleeve = CGRect(x: 190, y: 250, width: 470, height: 470)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: -8, height: -14), blur: 24, color: white(0, 0.45))
            Draw.upright(ctx, Vinyl.sleeve(side: 470, art: SampleArt.all[0], unit: 1), in: sleeve)
            ctx.restoreGState()
            let disc = CGRect(center: CGPoint(x: 600, y: 560), radius: 250)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: -10, height: -16), blur: 30, color: white(0, 0.5))
            Draw.upright(ctx, Vinyl.disc(diameter: 500, art: SampleArt.all[0], unit: 1), in: disc)
            ctx.restoreGState()
            Draw.upright(ctx, Vinyl.sheen(diameter: 500, unit: 1, strength: 1.6), in: disc)
            ctx.drawLinearGradient(makeGradient([(0, white(1, 0.12)), (0.5, white(1, 0)), (1, white(0, 0.15))]),
                                   start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
            ctx.restoreGState()
            ctx.stroke(.rounded(body.insetBy(dx: 1, dy: 1), 184), white(1, 0.18), width: 2)
        }
        write(image, to: url)
    }

    private static func snapshot(_ layer: CALayer, size: CGSize, scale: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: Draw.colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

/// Made-up album covers for previews and the icon.
enum SampleArt {
    static let all: [CGImage] = [goldenHour(), blueRooms(), fern(), staticCover()]

    private static let side: CGFloat = 600
    private static var full: CGRect { CGRect(x: 0, y: 0, width: side, height: side) }

    private static func goldenHour() -> CGImage {
        Draw.image(size: full.size, ppu: 1) { ctx in
            ctx.drawLinearGradient(makeGradient([(0, rgb(0xF7B267)), (0.55, rgb(0xF25C54)), (1, rgb(0x6A2C70))]),
                                   start: .zero, end: CGPoint(x: 0, y: side), options: [])
            ctx.fill(.ellipse(CGRect(center: CGPoint(x: 300, y: 330), radius: 160)), rgb(0xFFE6A0))
            for i in 0..<6 {
                let y = 360 + CGFloat(i) * 24
                ctx.fill(CGPath(rect: CGRect(x: 120, y: y, width: 360, height: 6 + CGFloat(i) * 2), transform: nil), rgb(0xE9575A))
            }
            Draw.text("GOLDEN HOUR", at: CGPoint(x: 40, y: 500), size: 54, weight: .black, color: white(1, 0.95), kern: 1)
            Draw.text("SIDE A · 33⅓", at: CGPoint(x: 42, y: 40), size: 20, weight: .semibold, color: white(1, 0.8), kern: 3)
        }
    }

    private static func blueRooms() -> CGImage {
        Draw.image(size: full.size, ppu: 1) { ctx in
            ctx.fill(CGPath(rect: full, transform: nil), rgb(0x1D3557))
            ctx.fill(CGPath(rect: CGRect(x: 60, y: 80, width: 300, height: 300), transform: nil), rgb(0x457B9D))
            ctx.fill(CGPath(rect: CGRect(x: 240, y: 220, width: 300, height: 220), transform: nil), rgb(0xA8DADC))
            ctx.fill(.ellipse(CGRect(center: CGPoint(x: 420, y: 160), radius: 70)), rgb(0xE63946))
            Draw.text("blue rooms", at: CGPoint(x: 60, y: 480), size: 64, weight: .light, color: white(1), kern: -1)
        }
    }

    private static func fern() -> CGImage {
        Draw.image(size: full.size, ppu: 1) { ctx in
            ctx.fill(CGPath(rect: full, transform: nil), rgb(0x2D4739))
            var rng = SplitMix64(seed: 3)
            for _ in 0..<40 {
                ctx.saveGState()
                ctx.translateBy(x: .random(in: 0...side, using: &rng), y: .random(in: 0...side, using: &rng))
                ctx.rotate(by: .random(in: 0...CGFloat.pi, using: &rng))
                let l = CGFloat.random(in: 60...160, using: &rng)
                ctx.fill(.ellipse(CGRect(x: -l / 2, y: -l / 7, width: l, height: l / 3.5)),
                         rgb(Bool.random(using: &rng) ? 0x6B9E6E : 0xA7C4A0, 0.85))
                ctx.restoreGState()
            }
            Draw.text("FERN", at: CGPoint(x: 40, y: 40), size: 90, weight: .heavy, color: rgb(0xF1EAD6), kern: 8)
        }
    }

    private static func staticCover() -> CGImage {
        Draw.image(size: full.size, ppu: 1) { ctx in
            ctx.fill(CGPath(rect: full, transform: nil), rgb(0xEDEAE4))
            for i in 0..<14 {
                ctx.stroke(.ellipse(CGRect(center: CGPoint(x: 330 + CGFloat(i) * 4, y: 280), radius: 30 + CGFloat(i) * 16)),
                           white(0.08), width: 5)
            }
            Draw.text("STATIC", at: CGPoint(x: 40, y: 520), size: 44, weight: .bold, color: white(0.08), kern: 12)
        }
    }
}
