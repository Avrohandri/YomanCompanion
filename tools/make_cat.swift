// Generates the bundled character pack: "Yoman", an original black pixel-art cat with a crisp white
// outline (readable on any wallpaper) and white eyes with slit pupils. Strictly black, white and greys.
//
//   swift tools/make_cat.swift Assets/cat

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGBA: Equatable { var r, g, b, a: UInt8 }

func hex(_ s: String) -> RGBA {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return RGBA(r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF), a: 255)
}

struct Fur { let body, rim: RGBA }
let blackFur = Fur(body: hex("#111111"), rim: hex("#2B2B2B"))
/// Overheat stays monochrome: the cat glows white-hot with a dark outline instead of turning red.
let hotFur = Fur(body: hex("#F4F4F4"), rim: hex("#FFFFFF"))

enum C {
    static let outline = hex("#F7F7F7"), glyphLine = hex("#141414")
    static let eye = hex("#FFFFFF"), eyeShade = hex("#D6D6D6"), lid = hex("#EDEDED")
    static let innerEar = hex("#3A3A3A"), nose = hex("#E6E6E6"), mouth = hex("#A8A8A8")
    static let mouthOpen = hex("#3A3A3A"), whisker = hex("#EDEDED"), bean = hex("#D9D9D9")
    static let keyTop = hex("#DCDCDC"), keyTopPressed = hex("#BEBEBE"), keySide = hex("#8E8E8E"), keyEdge = hex("#6B6B6B")
    static let bang = hex("#FFFFFF"), zzz = hex("#FFFFFF"), heart = hex("#FFFFFF")
    static let steam = hex("#FFFFFF"), sparkle = hex("#FFFFFF"), bubble = hex("#FFFFFF"), dot = hex("#2B2B2B")
    static let bowl = hex("#D0D0D0"), bowlShade = hex("#A6A6A6"), bowlRim = hex("#F0F0F0"), water = hex("#FFFFFF")
    static let phones = hex("#E6E6E6"), phonesShade = hex("#B5B5B5"), phonesBand = hex("#8A8A8A")
    static let noteA = hex("#FFFFFF"), noteB = hex("#D6D6D6")
    static let paper = hex("#F4F4F4"), paperShade = hex("#CCCCCC"), paperCore = hex("#8E8E8E")
}

final class Canvas {
    let w = 64, h = 64
    var px: [RGBA?] = Array(repeating: nil, count: 64 * 64)
    func set(_ x: Int, _ y: Int, _ c: RGBA) { if x >= 0, x < w, y >= 0, y < h { px[y * w + x] = c } }
    func get(_ x: Int, _ y: Int) -> RGBA? { x >= 0 && x < w && y >= 0 && y < h ? px[y * w + x] : nil }
    func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: RGBA) {
        guard x1 >= x0, y1 >= y0 else { return }
        for y in y0...y1 { for x in x0...x1 { set(x, y, c) } }
    }
    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: RGBA, maxY: Int = 61) {
        let y0 = max(0, Int(cy - ry) - 1), y1 = min(maxY, Int(cy + ry) + 1)
        let x0 = max(0, Int(cx - rx) - 1), x1 = min(w - 1, Int(cx + rx) + 1)
        guard y0 <= y1, x0 <= x1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { set(x, y, c) }
            }
        }
    }
    func triangle(tip: (Double, Double), left: Double, right: Double, baseY: Double, _ c: RGBA) {
        for y in Int(tip.1)...Int(baseY) {
            let t = (Double(y) - tip.1) / (baseY - tip.1)
            let xl = tip.0 + (left - tip.0) * t, xr = tip.0 + (right - tip.0) * t
            let a = Int(xl.rounded()), b = Int(xr.rounded())
            for x in min(a, b)...max(a, b) { set(x, y, c) }
        }
    }
    func stroke(_ pts: [(Double, Double)], radius: Double, _ c: RGBA) {
        for i in 0..<(pts.count - 1) {
            let (a, b) = (pts[i], pts[i + 1])
            let n = Int(hypot(b.0 - a.0, b.1 - a.1) * 3) + 1
            for k in 0...n {
                let t = Double(k) / Double(n)
                ellipse(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, radius, radius, c, maxY: 63)
            }
        }
    }
    func outline(_ c: RGBA) {
        var add: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where get(x, y) == nil {
            if [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { get(x + $0.0, y + $0.1) != nil }) { add.append((x, y)) }
        } }
        add.forEach { set($0.0, $0.1, c) }
    }
    func glyph(_ rows: [String], _ x0: Int, _ y0: Int, _ c: RGBA) {
        for (j, row) in rows.enumerated() { for (i, ch) in row.enumerated() where ch == "#" { set(x0 + i, y0 + j, c) } }
    }
    func merge(_ other: Canvas) {
        for i in 0..<px.count { if let p = other.px[i] { px[i] = p } }
    }
}

enum Body: Equatable { case sit, loaf, crouch, dangle, stretch(Int), peek, drink, air }
enum Eyes { case open, half, closed, happy }
enum Mouth { case none, meow, tongue, yawn }
enum Paws: Equatable { case down, keysL, keysR, keysBoth, wave(Int), tucked, bat(Bool) }
enum Extra { case bang(Bool), zzz(Int), dots(Int), hearts(Int), steam(Int), sparkle(Int), bowl, roll, keys(Int), headphones, notes(Int) }

struct Pose {
    var body = Body.sit
    var eyes = Eyes.open
    var mouth = Mouth.none
    var paws = Paws.down
    var tail = 0.0
    var bob = 0
    var lean = 0
    var hot = false
    var extras: [Extra] = []

    var head: (Int, Int) {
        switch body {
        case .sit, .air: return (lean, bob)
        case .loaf: return (0, 12 + bob)
        case .crouch: return (lean, 8 + bob)
        case .dangle: return (0, -3 + bob)
        case .stretch(let s): return (0, s == 0 ? 0 : -1)
        case .peek: return (0, 17 + bob)
        case .drink: return (0, 10 + bob)
        }
    }
    var eyeOffset: [Int] { [head.0, head.1] }
}

func sitTail(_ a: Double, lift: Double = 0) -> [(Double, Double)] {
    [(40, 58), (46, 59.5), (51, 58), (54 + a * 0.3, 54), (55.5 + a * 0.7, 49 - lift), (55 + a, 45 - lift * 1.5),
     (53 + a * 1.3, 41.5 - lift * 2)]
}

func draw(_ p: Pose) -> Canvas {
    let c = Canvas()
    let fur = p.hot ? hotFur : blackFur
    let (hx, hy) = p.head
    let cx = 32 + hx, cy = 30 + hy

    // Tail behind the body.
    switch p.body {
    case .sit, .drink: c.stroke(sitTail(p.tail), radius: 1.8, fur.body)
    case .air: c.stroke(sitTail(p.tail, lift: 2), radius: 1.8, fur.body)
    case .crouch:
        let t = p.tail
        c.stroke([(42, 55), (47, 50), (51, 44), (53 + t * 0.5, 38), (52 + t * 1.5, 33)], radius: 1.8, fur.body)
    case .stretch: c.stroke([(40, 57), (47, 56), (52, 52), (54, 47), (53, 41)], radius: 1.8, fur.body)
    default: break
    }

    // Body.
    let lean = Double(p.lean)
    switch p.body {
    case .sit, .drink:
        c.ellipse(32 + lean * 0.5, 50.5, 11.5, 11, fur.rim)
        c.ellipse(32.6 + lean * 0.5, 51.3, 11.1, 10.6, fur.body)
    case .air:
        c.ellipse(32, 49, 10.5, 11, fur.rim)
        c.ellipse(32.6, 49.8, 10.1, 10.6, fur.body)
    case .loaf:
        let b = Double(p.bob) * 0.5
        c.ellipse(32, 53.5 - b, 17, 8.5 + b, fur.rim)
        c.ellipse(32.6, 54.2 - b, 16.6, 8.2 + b, fur.body)
    case .crouch:
        c.ellipse(32 + lean, 54, 15, 7.5, fur.rim)
        c.ellipse(32.6 + lean, 54.6, 14.6, 7.2, fur.body)
        c.rect(22, 57, 27, 61, fur.body)
        c.rect(37, 57, 42, 61, fur.body)
    case .dangle:
        c.ellipse(32, 45, 8.5, 12.5, fur.rim)
        c.ellipse(32.5, 45.6, 8.1, 12, fur.body)
        let k = p.bob
        c.rect(26, 54, 28, 61 - k, fur.body)
        c.rect(36, 54, 38, 60 + k, fur.body)
        c.rect(23, 38, 25, 48 + k, fur.body)
        c.rect(39, 38, 41, 49 - k, fur.body)
        c.stroke([(33, 55), (35, 59), (39, 61.5), (44, 62)], radius: 1.6, fur.body)
    case .stretch(let s):
        c.ellipse(32, 46, 10, 15, fur.rim)
        c.ellipse(32.5, 46.6, 9.6, 14.6, fur.body)
        c.rect(24, 58, 29, 61, fur.body)
        c.rect(35, 58, 40, 61, fur.body)
        let top = [20, 12, 5][min(2, s)]
        c.rect(22, top, 25, 37, fur.body)
        c.rect(39, top, 42, 37, fur.body)
        c.rect(22, top, 25, top, fur.rim)
        c.rect(39, top, 42, top, fur.rim)
    case .peek: break
    }

    // Keyboard keys in front of the body, under the paws (bit 0 = left key pressed, bit 1 = right).
    for e in p.extras {
        if case .keys(let pressed) = e {
            for (i, x0) in [18, 35].enumerated() {
                let down = pressed & (1 << i) != 0
                let top = down ? 55 : 53
                c.rect(x0, top, x0 + 10, 57, down ? C.keyTopPressed : C.keyTop)
                c.rect(x0, 58, x0 + 10, 61, C.keySide)
                c.rect(x0 + 10, top, x0 + 10, 61, C.keyEdge)
                c.rect(x0, 61, x0 + 10, 61, C.keyEdge)
            }
        }
    }

    // Front legs and paws.
    func leg(_ x: Int, top: Int, bottom: Int) {
        c.rect(x, top, x + 3, bottom, fur.body)
        c.rect(x, top, x, bottom, fur.rim)
    }
    func lifted(_ x: Int, top: Int, bottom: Int) {
        leg(x, top: top, bottom: bottom)
        c.set(x + 1, bottom, C.bean)
        c.set(x + 2, bottom, C.bean)
    }
    if p.body == .sit || p.body == .air {
        switch p.paws {
        case .down: leg(26, top: 51, bottom: 61); leg(35, top: 51, bottom: 61)
        case .tucked: leg(26, top: 51, bottom: 57); leg(35, top: 51, bottom: 57)
        case .keysL: lifted(21, top: 44, bottom: 50); leg(39, top: 48, bottom: 54)
        case .keysR: leg(21, top: 48, bottom: 54); lifted(39, top: 44, bottom: 50)
        case .keysBoth: leg(21, top: 46, bottom: 52); leg(39, top: 46, bottom: 52)
        case .wave(let w):
            leg(26, top: 51, bottom: 61)
            let top = [37, 33, 30][min(2, w)]
            c.rect(43, top, 46, 50, fur.body)
            c.rect(43, top, 43, 50, fur.rim)
            c.set(44, top, C.bean); c.set(45, top, C.bean)
        case .bat(let out):
            leg(35, top: 51, bottom: 61)
            if out {
                c.rect(16, 49, 28, 52, fur.body)
                c.set(16, 50, C.bean); c.set(16, 51, C.bean)
            } else {
                leg(24, top: 49, bottom: 58)
            }
        }
    } else if p.body == .peek {
        c.rect(19, 55, 26, 60, fur.body)
        c.rect(38, 55, 45, 60, fur.body)
        c.rect(19, 55, 26, 55, fur.rim)
        c.rect(38, 55, 45, 55, fur.rim)
    }

    // Props that belong to the silhouette (they get the white outline).
    for e in p.extras {
        switch e {
        case .bowl:
            for (i, y) in (55...61).enumerated() { c.rect(19 + i / 2, y, 45 - i / 2, y, i == 0 ? C.bowlRim : C.bowl) }
            c.rect(21, 55, 43, 55, C.water)
            c.rect(40, 57, 43, 60, C.bowlShade)
        case .roll:
            c.rect(5, 51, 14, 59, C.paper)
            c.rect(12, 51, 14, 59, C.paperShade)
            c.ellipse(5.5, 55.5, 2.2, 4.5, C.paperShade)
            c.rect(5, 54, 5, 56, C.paperCore)
        default: break
        }
    }

    // Head.
    c.triangle(tip: (Double(cx - 10), Double(cy - 17)), left: Double(cx - 13), right: Double(cx - 2), baseY: Double(cy - 6), fur.body)
    c.triangle(tip: (Double(cx + 9), Double(cy - 17)), left: Double(cx + 1), right: Double(cx + 12), baseY: Double(cy - 6), fur.body)
    c.triangle(tip: (Double(cx) - 9.5, Double(cy) - 13.5), left: Double(cx - 11), right: Double(cx - 6), baseY: Double(cy - 8), C.innerEar)
    c.triangle(tip: (Double(cx) + 8.5, Double(cy) - 13.5), left: Double(cx + 5), right: Double(cx + 10), baseY: Double(cy - 8), C.innerEar)
    c.ellipse(Double(cx), Double(cy), 13, 10.5, fur.rim)
    c.ellipse(Double(cx) + 0.6, Double(cy) + 0.9, 12.6, 10.2, fur.body)
    c.set(cx - 14, cy + 3, fur.body); c.set(cx + 13, cy + 3, fur.body)

    for ex in [cx - 8, cx + 4] {
        switch p.eyes {
        case .open:
            c.rect(ex, cy - 3, ex + 3, cy + 1, C.eye)
            c.rect(ex, cy + 1, ex + 3, cy + 1, C.eyeShade)
            for (x, y) in [(ex, cy - 3), (ex + 3, cy - 3), (ex, cy + 1), (ex + 3, cy + 1)] { c.set(x, y, fur.body) }
        case .half:
            c.rect(ex, cy - 1, ex + 3, cy + 1, C.eye)
            c.rect(ex, cy - 1, ex + 3, cy - 1, C.lid)
            c.set(ex, cy + 1, fur.body); c.set(ex + 3, cy + 1, fur.body)
        case .closed:
            c.set(ex, cy - 1, C.lid); c.set(ex + 1, cy, C.lid); c.set(ex + 2, cy, C.lid); c.set(ex + 3, cy - 1, C.lid)
        case .happy:
            c.set(ex, cy, C.lid); c.set(ex + 1, cy - 1, C.lid); c.set(ex + 2, cy - 1, C.lid); c.set(ex + 3, cy, C.lid)
        }
    }
    c.rect(cx - 1, cy + 3, cx, cy + 3, C.nose)
    switch p.mouth {
    case .none:
        for (x, y) in [(cx - 3, cy + 5), (cx - 2, cy + 6), (cx - 1, cy + 5), (cx, cy + 5), (cx + 1, cy + 6), (cx + 2, cy + 5)] {
            c.set(x, y, C.mouth)
        }
    case .meow:
        c.rect(cx - 2, cy + 5, cx + 1, cy + 7, C.mouthOpen)
        c.rect(cx - 1, cy + 7, cx, cy + 7, C.nose)
    case .tongue: c.rect(cx - 1, cy + 5, cx, cy + 7, C.nose)
    case .yawn:
        c.rect(cx - 3, cy + 4, cx + 2, cy + 8, C.mouthOpen)
        c.rect(cx - 2, cy + 8, cx + 1, cy + 8, C.nose)
    }

    if p.body == .loaf {
        c.stroke([(47, 58), (42, 60), (34, 60.5), (24, 60.5), (18, 58.5)], radius: 1.5, fur.body)
    }
    for e in p.extras {
        if case .headphones = e {
            // Band over the head between the ears, cups over the cheeks.
            c.stroke([(Double(cx) - 12.5, Double(cy) - 2), (Double(cx) - 9, Double(cy) - 10), (Double(cx) - 0.5, Double(cy) - 12.5),
                      (Double(cx) + 8, Double(cy) - 10), (Double(cx) + 11.5, Double(cy) - 2)], radius: 0.9, C.phonesBand)
            c.rect(cx - 15, cy - 3, cx - 12, cy + 4, C.phones)
            c.rect(cx - 15, cy + 2, cx - 12, cy + 4, C.phonesShade)
            c.rect(cx + 11, cy - 3, cx + 14, cy + 4, C.phones)
            c.rect(cx + 11, cy + 2, cx + 14, cy + 4, C.phonesShade)
        }
    }

    c.outline(p.hot ? C.glyphLine : C.outline)

    let mirror = { (x: Int) in 2 * cx - 1 - x }
    for (x, y) in [(cx - 16, cy + 2), (cx - 15, cy + 2), (cx - 14, cy + 3), (cx - 13, cy + 3),
                   (cx - 16, cy + 6), (cx - 15, cy + 5), (cx - 14, cy + 5)] {
        c.set(x, y, C.whisker)
        c.set(mirror(x), y, C.whisker)
    }

    // Floating effects get their own dark outline so they read on light and dark backgrounds.
    let fx = Canvas()
    for e in p.extras {
        switch e {
        case .bang(let on):
            if on { fx.rect(51, 4, 52, 11, C.bang); fx.rect(51, 13, 52, 14, C.bang) }
        case .zzz(let i):
            let k = i % 4
            fx.glyph(["####", "..#.", ".#..", "####"], 45 + k / 2, 31 - k, C.zzz)
            if k >= 2 { fx.glyph(["#####", "...#.", "..#..", ".#...", "#####"], 51, 22 - (k - 2), C.zzz) }
        case .dots(let i):
            fx.rect(43, 6, 56, 11, C.bubble)
            for k in 0..<3 {
                let lift = (i % 6) == k || (i % 6) == k + 3 ? 1 : 0
                fx.rect(45 + k * 4, 8 - lift, 46 + k * 4, 9 - lift, C.dot)
            }
        case .hearts(let i):
            let heart = [".#.#.", "#####", ".###.", "..#.."]
            fx.glyph(heart, 8, 21 - 2 * (i % 4), C.heart)
            fx.glyph(heart, 50, 15 - 2 * ((i + 2) % 4), C.heart)
        case .steam(let i):
            for (k, x) in [14, 30, 46].enumerated() {
                let y = 9 - ((i + k) % 3) * 2
                fx.rect(x, y, x + 2, y + 1, C.steam)
                fx.set(x + 1, y - 1, C.steam)
            }
        case .notes(let i):
            let eighth = ["..##", "..#.", "..#.", "###.", "##.."]
            let k = i % 4
            fx.glyph(eighth, 6, 24 - k * 2, k % 2 == 0 ? C.noteA : C.noteB)
            fx.glyph(eighth, 52, 16 - ((k + 2) % 4) * 2, k % 2 == 0 ? C.noteB : C.noteA)
        case .sparkle(let i):
            for (x, y) in i % 2 == 0 ? [(11, 30), (52, 20)] : [(9, 22), (54, 31)] {
                fx.set(x, y, C.sparkle)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { fx.set(x + dx, y + dy, C.sparkle) }
            }
        default: break
        }
    }
    fx.outline(C.glyphLine)
    c.merge(fx)
    return c
}

struct StateDef {
    let name: String
    let poses: [Pose]
    let durations: [Int]
    let loop: Bool
    var eyes = true
    var next: String? = nil
}

func P(_ f: (inout Pose) -> Void) -> Pose { var p = Pose(); f(&p); return p }

let sway: [Double] = [0, 0.7, 1.4, 2, 1.4, 0.7, 0, -0.7]

let states: [StateDef] = [
    StateDef(name: "idle", poses: sway.enumerated().map { i, t in P { $0.tail = t; $0.bob = (i >= 2 && i <= 5) ? 1 : 0 } },
             durations: Array(repeating: 190, count: 8), loop: true),
    StateDef(name: "blink", poses: [P { $0.eyes = .half }, P { $0.eyes = .closed }, P { $0.eyes = .half }],
             durations: [50, 80, 50], loop: false, eyes: false, next: "idle"),
    StateDef(name: "working", poses: (0..<6).map { i in P { $0.tail = sway[i] * 0.5; $0.extras = [.dots(i)] } },
             durations: Array(repeating: 200, count: 6), loop: true),
    StateDef(name: "needs_you",
             poses: [0, 1, 2, 1].enumerated().map { i, w in P { $0.paws = .wave(w); $0.mouth = i == 2 ? .meow : .none
                 $0.tail = 2; $0.extras = [.bang(i < 3)] } },
             durations: [140, 140, 220, 140], loop: true),
    StateDef(name: "done",
             poses: [P { $0.bob = 2; $0.paws = .tucked; $0.eyes = .happy },
                     P { $0.body = .air; $0.paws = .tucked; $0.eyes = .happy; $0.mouth = .meow; $0.tail = 2; $0.extras = [.sparkle(0)] },
                     P { $0.body = .air; $0.paws = .tucked; $0.eyes = .happy; $0.mouth = .meow; $0.tail = 2; $0.extras = [.sparkle(1)] },
                     P { $0.bob = 2; $0.eyes = .happy },
                     P { $0.eyes = .happy; $0.tail = 1 }],
             durations: [90, 200, 200, 110, 380], loop: false, next: "idle"),
    StateDef(name: "sleep", poses: (0..<4).map { i in P { $0.body = .loaf; $0.eyes = .closed; $0.bob = i == 1 || i == 2 ? 1 : 0
                 $0.extras = [.zzz(i)] } },
             durations: [700, 700, 700, 700], loop: true, eyes: false),
    StateDef(name: "dragged", poses: (0..<4).map { i in P { $0.body = .dangle; $0.bob = i % 2; $0.mouth = i < 2 ? .meow : .none } },
             durations: [150, 150, 150, 150], loop: true),
    StateDef(name: "greet",
             poses: [1, 2, 1, 2, 0].map { w in P { $0.paws = .wave(w); $0.mouth = w == 2 ? .meow : .none; $0.tail = 2 } },
             durations: [130, 130, 130, 130, 200], loop: false, next: "idle"),
    StateDef(name: "typing",
             poses: [Paws.keysL, .keysBoth, .keysR, .keysBoth].enumerated().map { i, k in
                 P { $0.paws = k; $0.tail = sway[i * 2]; $0.extras = [.keys(i == 0 ? 2 : i == 2 ? 1 : 0)] } },
             durations: [110, 70, 110, 70], loop: true),
    StateDef(name: "overheat",
             poses: [Paws.keysL, .keysBoth, .keysR, .keysBoth].enumerated().map { i, k in
                 P { $0.paws = k; $0.hot = true; $0.mouth = .meow; $0.tail = 2
                     $0.extras = [.keys(i == 0 ? 2 : i == 2 ? 1 : 0), .steam(i)] } },
             durations: [70, 50, 70, 50], loop: true),
    StateDef(name: "petted", poses: (0..<4).map { i in P { $0.eyes = .happy; $0.bob = i % 2; $0.lean = [0, 1, 0, -1][i]
                 $0.tail = sway[i * 2]; $0.extras = [.hearts(i)] } },
             durations: [200, 200, 200, 200], loop: true, eyes: false),
    StateDef(name: "stretch",
             poses: [P { $0.body = .stretch(0); $0.eyes = .closed }, P { $0.body = .stretch(1); $0.eyes = .closed },
                     P { $0.body = .stretch(2); $0.eyes = .closed }, P { $0.body = .stretch(2); $0.eyes = .closed; $0.mouth = .yawn },
                     P { $0.body = .stretch(2); $0.eyes = .closed; $0.mouth = .yawn }, P { $0.body = .stretch(1); $0.eyes = .closed }],
             durations: [260, 260, 400, 500, 500, 260], loop: true, eyes: false),
    StateDef(name: "drink", poses: (0..<4).map { i in P { $0.body = .drink; $0.eyes = .closed; $0.bob = i % 2
                 $0.mouth = i % 2 == 0 ? .tongue : .none; $0.extras = [.bowl] } },
             durations: [180, 180, 180, 180], loop: true, eyes: false),
    StateDef(name: "paper", poses: [true, false, true, false].enumerated().map { i, out in
                 P { $0.paws = .bat(out); $0.extras = [.roll]; $0.tail = sway[i * 2] } },
             durations: [130, 130, 130, 130], loop: true),
    StateDef(name: "listening",
             poses: (0..<4).map { i in P { $0.eyes = .happy; $0.bob = i % 2; $0.lean = [-1, 0, 1, 0][i]
                 $0.tail = sway[(i * 2) % 8]; $0.extras = [.headphones, .notes(i)] } },
             durations: [240, 240, 240, 240], loop: true, eyes: false),
    StateDef(name: "peek", poses: [P { $0.body = .peek }, P { $0.body = .peek; $0.bob = 1 },
                                   P { $0.body = .peek; $0.bob = 1; $0.eyes = .half }, P { $0.body = .peek }],
             durations: [900, 700, 120, 700], loop: true),
]

// MARK: Write sheet + JSON

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/cat")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let cols = states.map(\.poses.count).max()!
let sheetW = cols * 64, sheetH = states.count * 64
var bytes = [UInt8](repeating: 0, count: sheetW * sheetH * 4)
var colors = Set<UInt32>()
for (row, s) in states.enumerated() {
    for (col, pose) in s.poses.enumerated() {
        let canvas = draw(pose)
        for y in 0..<64 { for x in 0..<64 {
            guard let p = canvas.get(x, y) else { continue }
            let i = ((row * 64 + y) * sheetW + col * 64 + x) * 4
            bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = 255
            colors.insert(UInt32(p.r) << 16 | UInt32(p.g) << 8 | UInt32(p.b))
        } }
    }
}

let ctx = CGContext(data: &bytes, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: sheetW * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let pngURL = outDir.appendingPathComponent("sheet.png")
let dest = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))

var stateJSON: [String: Any] = [:]
for (row, s) in states.enumerated() {
    var d: [String: Any] = [
        "row": row, "frames": Array(0..<s.poses.count), "durations_ms": s.durations, "loop": s.loop,
        "eyes": s.eyes, "eye_offsets": s.poses.map(\.eyeOffset),
    ]
    if let n = s.next { d["next"] = n }
    stateJSON[s.name] = d
}
let spec: [String: Any] = [
    "name": "yoman-cat",
    "sheet": "sheet.png",
    "cell_width": 64, "cell_height": 64, "scale": 2,
    "eyes": ["left": [25, 28], "right": [37, 28], "pupil": [2, 3], "range": [1, 1], "color": "#0E0C12"],
    "paper": ["x": 5, "y": 57, "height": 3],
    "states": stateJSON,
]
let json = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("character.json"))
print("Wrote \(pngURL.path) (\(sheetW)x\(sheetH), \(colors.count) colors, \(states.count) states)")
