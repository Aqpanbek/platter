import CoreGraphics
import Foundation

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Classic 2D gradient noise.
struct Perlin {
    private let p: [Int]

    init(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var perm = Array(0..<256)
        perm.shuffle(using: &rng)
        p = perm + perm
    }

    func noise(_ x: Double, _ y: Double) -> Double {
        let xf = x.rounded(.down), yf = y.rounded(.down)
        let xi = Int(xf) & 255, yi = Int(yf) & 255
        let x = x - xf, y = y - yf
        let u = fade(x), v = fade(y)
        let aa = p[p[xi] + yi], ab = p[p[xi] + yi + 1]
        let ba = p[p[xi + 1] + yi], bb = p[p[xi + 1] + yi + 1]
        let x1 = lerp(grad(aa, x, y), grad(ba, x - 1, y), u)
        let x2 = lerp(grad(ab, x, y - 1), grad(bb, x - 1, y - 1), u)
        return lerp(x1, x2, v)
    }

    func fbm(_ x: Double, _ y: Double, octaves: Int) -> Double {
        var sum = 0.0, amp = 0.5, f = 1.0
        for _ in 0..<octaves {
            sum += amp * noise(x * f, y * f)
            f *= 2.03
            amp *= 0.5
        }
        return sum
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    private func grad(_ h: Int, _ x: Double, _ y: Double) -> Double {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x
        case 5: return -x
        case 6: return y
        default: return -y
        }
    }
}

@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
@inline(__always) func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

struct WoodStyle {
    var dark: SIMD3<Double>
    var mid: SIMD3<Double>
    var light: SIMD3<Double>
    /// Grain lines per unit across the board.
    var rings: Double = 22
    /// Streak density across the board.
    var streaks: Double = 34
    var seed: UInt64 = 1

    static func hex(_ v: UInt32) -> SIMD3<Double> {
        SIMD3(Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }
}

enum Texture {
    /// Procedural wood. `mapping` turns a normalized pixel position (0…1, top-left origin)
    /// into wood space: u runs along the grain, v across it.
    static func wood(width: Int, height: Int, style: WoodStyle,
                     mapping: (Double, Double) -> (Double, Double)) -> CGImage {
        let perlin = Perlin(seed: style.seed)
        var buf = [UInt8](repeating: 255, count: width * height * 4)
        buf.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let ny = (Double(y) + 0.5) / Double(height)
                for x in 0..<width {
                    let (u, v) = mapping((Double(x) + 0.5) / Double(width), ny)
                    let warp = perlin.fbm(u * 0.45, v * 1.4, octaves: 3)
                    let ring = (v + warp * 0.035) * style.rings
                    let r = ring - ring.rounded(.down)
                    let late = smoothstep(0.72, 0.97, r) * (0.6 + 0.8 * perlin.noise(u * 0.8, ring * 0.37))
                    let streak = perlin.fbm(u * 0.5 + 17, v * style.streaks, octaves: 5)
                    let fiber = perlin.noise(u * 30, v * 700)
                    let tone = perlin.fbm(u * 0.25 + 5, v * 0.9 + 9, octaves: 2)
                    let t = clamp01(0.58 + 0.46 * streak - 0.17 * late + 0.07 * fiber + 0.26 * tone)
                    let c = t < 0.5
                        ? style.dark + (style.mid - style.dark) * (t * 2)
                        : style.mid + (style.light - style.mid) * ((t - 0.5) * 2)
                    let i = (y * width + x) * 4
                    out[i] = UInt8(clamping: Int(c.x))
                    out[i + 1] = UInt8(clamping: Int(c.y))
                    out[i + 2] = UInt8(clamping: Int(c.z))
                }
            }
        }
        return makeImage(buf, width: width, height: height)
    }

    /// Fine, horizontally brushed speckle for painted / anodised surfaces. Tiles seamlessly.
    static func brushed(size: Int = 256, seed: UInt64 = 9, strength: Double = 0.07) -> CGImage {
        var rng = SplitMix64(seed: seed)
        let raw = (0..<(size * size)).map { _ in Double.random(in: -1...1, using: &rng) }
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        let smear = 9
        for y in 0..<size {
            for x in 0..<size {
                var s = 0.0
                for d in -smear...smear { s += raw[y * size + (x + d + size) % size] }
                let v = s / Double(smear * 2 + 1) * 2.4
                let a = min(1, abs(v)) * strength
                let i = (y * size + x) * 4
                let c: Double = v > 0 ? 255 : 0
                buf[i] = UInt8(c * a)
                buf[i + 1] = UInt8(c * a)
                buf[i + 2] = UInt8(c * a)
                buf[i + 3] = UInt8(255 * a)
            }
        }
        return makeImage(buf, width: size, height: size)
    }

    /// Polished concrete: soft mottling plus scattered light and dark specks.
    /// `scale` is texture pixels per design unit, so features keep their size on any screen.
    static func concrete(width: Int, height: Int, scale: Double, base: SIMD3<Double>, seed: UInt64) -> CGImage {
        let perlin = Perlin(seed: seed)
        var rng = SplitMix64(seed: seed &+ 1)
        var buf = [UInt8](repeating: 255, count: width * height * 4)
        buf.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x) / scale, dy = Double(y) / scale
                    let mottle = perlin.fbm(dx * 0.004, dy * 0.004, octaves: 4)
                    let cloud = perlin.fbm(dx * 0.03 + 3, dy * 0.03, octaves: 3)
                    let grain = Double.random(in: -1...1, using: &rng)
                    let f = 1 + 0.10 * mottle + 0.035 * cloud + 0.022 * grain
                    let i = (y * width + x) * 4
                    out[i] = UInt8(clamping: Int(base.x * f))
                    out[i + 1] = UInt8(clamping: Int(base.y * f))
                    out[i + 2] = UInt8(clamping: Int(base.z * f))
                }
            }
            let specks = width * height / 700
            for _ in 0..<specks {
                let x = Int.random(in: 0..<width, using: &rng), y = Int.random(in: 0..<height, using: &rng)
                let dark = Bool.random(using: &rng)
                let v = dark ? Double.random(in: 0.55...0.8, using: &rng) : Double.random(in: 1.06...1.15, using: &rng)
                let i = (y * width + x) * 4
                for c in 0..<3 { out[i + c] = UInt8(clamping: Int(Double(out[i + c]) * v)) }
            }
        }
        return makeImage(buf, width: width, height: height)
    }

    /// Felt desk mat: fine fibres with a faint woven rhythm.
    static func felt(width: Int, height: Int, scale: Double, base: SIMD3<Double>, seed: UInt64) -> CGImage {
        let perlin = Perlin(seed: seed)
        var rng = SplitMix64(seed: seed &+ 7)
        var buf = [UInt8](repeating: 255, count: width * height * 4)
        buf.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x) / scale, dy = Double(y) / scale
                    let fibre = perlin.noise(dx * 0.9, dy * 0.9)
                    let tone = perlin.fbm(dx * 0.003, dy * 0.003, octaves: 3)
                    let weave = sin(dx * 1.6) * sin(dy * 1.6)
                    let f = 1 + 0.06 * fibre + 0.08 * tone + 0.012 * weave + 0.03 * Double.random(in: -1...1, using: &rng)
                    let i = (y * width + x) * 4
                    out[i] = UInt8(clamping: Int(base.x * f))
                    out[i + 1] = UInt8(clamping: Int(base.y * f))
                    out[i + 2] = UInt8(clamping: Int(base.z * f))
                }
            }
        }
        return makeImage(buf, width: width, height: height)
    }

    /// Mean colour of an image (sampled from a 12×12 thumbnail).
    static func averageColor(_ image: CGImage) -> SIMD3<Double> {
        let n = 12
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                            space: Draw.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        var sum = SIMD3<Double>(0, 0, 0)
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += SIMD3(Double(px[i]), Double(px[i + 1]), Double(px[i + 2]))
        }
        return sum / Double(n * n)
    }

    static func makeImage(_ buf: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(buf) as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: Draw.colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }
}
