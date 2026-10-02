import AppKit
import QuartzCore

/// Images of the record itself and its sleeve. All sizes are design units; `unit` is pixels per unit.
enum Vinyl {
    static let labelRatio: CGFloat = 0.31

    /// The record face: grooves, run-out and a label printed with the album art. Rotates as one piece.
    static func disc(diameter d: CGFloat, art: CGImage?, unit: CGFloat) -> CGImage {
        Draw.image(size: CGSize(width: d, height: d), ppu: unit) { ctx in
            let c = CGPoint(x: d / 2, y: d / 2), r = d / 2, rl = r * labelRatio
            let circle = { (radius: CGFloat) in CGRect(center: c, radius: radius) }

            ctx.fill(.ellipse(circle(r)), rgb(0x0B0B0C))
            ctx.fill(.ellipse(circle(r)), radial: makeGradient([(0, white(0.13)), (1, white(0.04))]),
                     center: c, radius: r, startRadius: rl)

            // Grooves: hundreds of faint rings with random spacing and brightness.
            var rng = SplitMix64(seed: 7)
            var gr = rl + r * 0.06
            ctx.setLineWidth(0.55)
            while gr < r * 0.968 {
                ctx.setStrokeColor(white(1, .random(in: 0.012...0.07, using: &rng)))
                ctx.strokeEllipse(in: circle(gr))
                gr += .random(in: 0.9...2.2, using: &rng)
            }
            // Gaps between tracks.
            for g: CGFloat in [0.49, 0.61, 0.74, 0.86] {
                ctx.stroke(.ellipse(circle(r * g)), white(0, 0.85), width: 2.4)
                ctx.stroke(.ellipse(circle(r * g + 1.6)), white(1, 0.06), width: 0.6)
            }
            // Raised lip at the rim.
            ctx.stroke(.ellipse(circle(r * 0.982)), white(1, 0.10), width: r * 0.018)
            ctx.stroke(.ellipse(circle(r - 0.6)), white(0, 0.9), width: 1.2)
            // Glossy run-out around the label.
            ctx.saveGState()
            ctx.addEllipse(in: circle(rl + r * 0.055))
            ctx.addEllipse(in: circle(rl))
            ctx.clip(using: .evenOdd)
            ctx.fill(.ellipse(circle(rl + r * 0.055)), rgb(0x161617))
            ctx.restoreGState()

            // Label.
            ctx.saveGState()
            ctx.addEllipse(in: circle(rl))
            ctx.clip()
            if let art {
                Draw.aspectFill(ctx, art, in: circle(rl))
            } else {
                placeholderLabel(ctx, center: c, radius: rl)
            }
            ctx.drawRadialGradient(makeGradient([(0, white(0, 0)), (0.78, white(0, 0)), (1, white(0, 0.32))]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: rl, options: [])
            ctx.restoreGState()
            ctx.stroke(.ellipse(circle(rl)), white(0, 0.55), width: 1.2)

            // Spindle.
            ctx.fill(.ellipse(circle(r * 0.024)), radial: makeGradient([(0, white(0.95)), (1, white(0.55))]),
                     center: CGPoint(x: c.x - r * 0.008, y: c.y - r * 0.008), radius: r * 0.026)
            ctx.stroke(.ellipse(circle(r * 0.024)), white(0, 0.5), width: 0.8)
        }
    }

    /// Light reflected by the grooves. Stays still while the disc turns underneath, which is what
    /// makes a spinning record read as spinning.
    static func sheen(diameter d: CGFloat, unit: CGFloat, strength: CGFloat = 1) -> CGImage {
        Draw.image(size: CGSize(width: d, height: d), ppu: unit) { ctx in
            let c = CGPoint(x: d / 2, y: d / 2), r = d / 2
            ctx.addEllipse(in: CGRect(center: c, radius: r * 0.975))
            ctx.addEllipse(in: CGRect(center: c, radius: r * labelRatio + r * 0.05))
            ctx.clip(using: .evenOdd)
            let s = strength
            let g = makeGradient([
                (0.00, white(1, 0)), (0.07, white(1, 0.10 * s)), (0.115, white(1, 0.20 * s)),
                (0.16, white(1, 0.08 * s)), (0.24, white(1, 0)), (0.50, white(1, 0)),
                (0.57, white(1, 0.07 * s)), (0.615, white(1, 0.15 * s)), (0.66, white(1, 0.06 * s)),
                (0.74, white(1, 0)), (1.00, white(1, 0)),
            ])
            ctx.drawConicGradient(g, center: c, angle: -.pi * 0.30)
        }
    }

    /// Square album sleeve with a touch of print texture and ring wear.
    static func sleeve(side s: CGFloat, art: CGImage?, unit: CGFloat, border: CGFloat = 0) -> CGImage {
        Draw.image(size: CGSize(width: s, height: s), ppu: unit) { ctx in
            let full = CGRect(x: 0, y: 0, width: s, height: s)
            if border > 0 { ctx.fill(CGPath(rect: full, transform: nil), rgb(0xF3F1EC)) }
            let face = full.insetBy(dx: border, dy: border)
            if let art {
                Draw.aspectFill(ctx, art, in: face)
            } else {
                ctx.fill(CGPath(rect: face, transform: nil), rgb(0xD8CCB4))
                Draw.text("PLATTER", at: CGPoint(x: s / 2, y: s / 2 - s * 0.03), size: s * 0.06, weight: .bold,
                          color: rgb(0x6E6250), kern: s * 0.012, centered: true)
            }
            // Ring wear from the record inside.
            ctx.stroke(.ellipse(CGRect(center: face.center, radius: s * 0.43)), white(1, 0.05), width: s * 0.04)
            // Soft light falloff across the cardboard.
            ctx.drawLinearGradient(makeGradient([(0, white(1, 0.10)), (0.45, white(1, 0)), (1, white(0, 0.14))]),
                                   start: .zero, end: CGPoint(x: s, y: s), options: [])
            ctx.stroke(CGPath(rect: full.insetBy(dx: 0.5, dy: 0.5), transform: nil), white(0, 0.28), width: 1)
            ctx.stroke(CGPath(rect: full.insetBy(dx: 1.6, dy: 1.6), transform: nil), white(1, 0.12), width: 1)
        }
    }

    private static func placeholderLabel(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat) {
        ctx.fill(.ellipse(CGRect(center: c, radius: r)), rgb(0xE9DFC8))
        ctx.stroke(.ellipse(CGRect(center: c, radius: r * 0.82)), rgb(0xB5442E), width: r * 0.05)
        Draw.text("PLATTER", at: CGPoint(x: c.x, y: c.y - r * 0.42), size: r * 0.16, weight: .heavy,
                  color: rgb(0x5A4A3A), kern: r * 0.03, centered: true)
        Draw.text("33⅓", at: CGPoint(x: c.x, y: c.y + r * 0.22), size: r * 0.13, weight: .medium,
                  color: rgb(0x5A4A3A), centered: true)
    }
}

extension CAFrameRateRange {
    /// Slow ambient motion doesn't need ProMotion's 120 Hz; capping it saves GPU time and battery.
    static let ambient = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
}

/// Keeps a layer turning (33⅓ rpm by default), pausing and resuming without jumping.
final class Spinner {
    let layer: CALayer
    private let period: CFTimeInterval
    private let clockwise: Bool

    init(layer: CALayer, period: CFTimeInterval = 60 / 33.333, clockwise: Bool = true) {
        self.layer = layer
        self.period = period
        self.clockwise = clockwise
    }

    func set(spinning: Bool) {
        if layer.animation(forKey: "spin") == nil {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = 0
            a.toValue = (clockwise ? -2 : 2) * Double.pi
            a.duration = period
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            a.preferredFrameRateRange = .ambient
            layer.add(a, forKey: "spin")
        }
        spinning ? resume() : pause()
    }

    private func pause() {
        guard layer.speed != 0 else { return }
        let t = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = t
    }

    private func resume() {
        guard layer.speed == 0 else { return }
        let paused = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
    }
}
