import AppKit
import CoreImage

// MARK: - Design canvas

/// Scenes are laid out on a fixed 1600×1040 design canvas (the aspect of a MacBook display)
/// and scaled to fill the real screen, centred, cropping whatever overflows.
struct Canvas {
    static let design = CGSize(width: 1600, height: 1040)

    let size: CGSize
    let scale: CGFloat
    let k: CGFloat
    let origin: CGPoint

    init(size: CGSize, scale: CGFloat) {
        self.size = size
        self.scale = scale
        k = max(size.width / Self.design.width, size.height / Self.design.height)
        origin = CGPoint(x: (size.width - Self.design.width * k) / 2,
                         y: (size.height - Self.design.height * k) / 2)
    }

    /// Bitmap pixels per design unit.
    var unit: CGFloat { k * scale }

    /// Design rect (top-left origin) → layer rect (bottom-left origin).
    func rect(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + r.minX * k, y: size.height - origin.y - r.maxY * k,
               width: r.width * k, height: r.height * k)
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * k, y: size.height - origin.y - p.y * k)
    }

    var designRect: CGRect { rect(CGRect(origin: .zero, size: Self.design)) }

    /// Makes a context from `Draw.image(size: canvas.size, ppu: canvas.scale)` draw in design units.
    func enterDesignSpace(_ ctx: CGContext) {
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: k, y: k)
    }
}

// MARK: - Bitmap helpers

enum Draw {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Bitmap of `size` drawing units at `ppu` pixels per unit. The context is flipped so drawing
    /// uses a top-left origin; the resulting image is upright.
    static func image(size: CGSize, ppu: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * ppu).rounded(.up)))
        let h = max(1, Int((size.height * ppu).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return render(ctx, height: h, ppu: ppu, body)
    }

    /// Grayscale bitmap (white = opaque) for soft clipping masks.
    static func mask(size: CGSize, ppu: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * ppu).rounded(.up)))
        let h = max(1, Int((size.height * ppu).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return render(ctx, height: h, ppu: ppu, body)
    }

    private static func render(_ ctx: CGContext, height: Int, ppu: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: ppu, y: -ppu)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// Draws an upright image into a flipped context.
    static func upright(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func aspectFill(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let s = max(rect.width / iw, rect.height / ih)
        let r = CGRect(x: rect.midX - iw * s / 2, y: rect.midY - ih * s / 2, width: iw * s, height: ih * s)
        ctx.saveGState()
        ctx.clip(to: rect)
        upright(ctx, image, in: r)
        ctx.restoreGState()
    }

    /// Intersects the clip with a grayscale mask laid over `rect` (flipped-context aware).
    static func clip(_ ctx: CGContext, toMask mask: CGImage, in rect: CGRect) {
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.clip(to: CGRect(origin: .zero, size: rect.size), mask: mask)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.maxY)
    }

    static func blur(_ image: CGImage, sigma: Double, gray: Bool = false) -> CGImage {
        let input = CIImage(cgImage: image)
        let out = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        if gray {
            return ciContext.createCGImage(out, from: input.extent, format: .L8,
                                           colorSpace: CGColorSpaceCreateDeviceGray())!
        }
        return ciContext.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: colorSpace)!
    }

    /// Shadow for subsequent fills. Offsets in design units, +dy is down; `unit` = pixels per design unit.
    static func shadow(_ ctx: CGContext, dx: CGFloat, dy: CGFloat, blur: CGFloat, color: CGColor, unit: CGFloat) {
        ctx.setShadow(offset: CGSize(width: dx * unit, height: -dy * unit), blur: blur * unit, color: color)
    }

    /// Paints only the blurred shadow of `path`; the shape itself lands far off-canvas.
    static func castShadow(_ ctx: CGContext, _ path: CGPath, dx: CGFloat, dy: CGFloat, blur: CGFloat,
                           color: CGColor, unit: CGFloat) {
        let away: CGFloat = 20000
        ctx.saveGState()
        shadow(ctx, dx: dx + away, dy: dy, blur: blur, color: color, unit: unit)
        ctx.translateBy(x: -away, y: 0)
        ctx.addPath(path)
        ctx.setFillColor(.black)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold,
                     color: CGColor, kern: CGFloat = 0, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color) ?? .white,
            .kern: kern,
        ]
        let s = NSAttributedString(string: string, attributes: attrs)
        var p = point
        if centered { p.x -= s.size().width / 2 }
        s.draw(at: p)
    }
}

// MARK: - Colors & geometry

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func white(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: w, green: w, blue: w, alpha: a)
}

func makeGradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: Draw.colorSpace, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    init(center: CGPoint, rx: CGFloat, ry: CGFloat) {
        self.init(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPath {
    static func polygon(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points)
        p.closeSubpath()
        return p
    }

    static func ellipse(_ rect: CGRect) -> CGPath { CGPath(ellipseIn: rect, transform: nil) }

    static func rounded(_ rect: CGRect, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// A square of `side` lying flat on a tilted surface: rotated, then squashed vertically.
    static func flatSquare(center: CGPoint, side: CGFloat, angle: CGFloat, tilt: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: 1, y: tilt).rotated(by: angle)
        return CGPath(rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side), transform: &t)
    }
}

extension CGContext {
    /// Not imported as a method in the Swift overlay, so call the C function.
    func drawConicGradient(_ gradient: CGGradient, center: CGPoint, angle: CGFloat) {
        CGContextDrawConicGradient(self, gradient, center, angle)
    }

    func fill(_ path: CGPath, _ color: CGColor) {
        addPath(path)
        setFillColor(color)
        fillPath()
    }

    func fill(_ path: CGPath, linear g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState()
        addPath(path)
        clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func fill(_ path: CGPath, radial g: CGGradient, center: CGPoint, radius: CGFloat, startRadius: CGFloat = 0) {
        saveGState()
        addPath(path)
        clip()
        drawRadialGradient(g, startCenter: center, startRadius: startRadius, endCenter: center, endRadius: radius,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat) {
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        strokePath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ color: CGColor, width: CGFloat, cap: CGLineCap = .butt) {
        move(to: a)
        addLine(to: b)
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        strokePath()
    }
}

extension NSImage {
    var cg: CGImage? {
        var r = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &r, context: nil, hints: nil)
    }
}

func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}
