// Renders README images from the character pack: an animated demo GIF and a labeled grid of every state.
//
//   swift tools/make_demo.swift Assets/cat .github

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StateSpec: Decodable {
    let row: Int
    let frames: [Int]
    let durations_ms: [Int]
    let eyes: Bool?
    let eye_offsets: [[Int]]?
}
struct Eyes: Decodable { let left: [Int]; let right: [Int]; let pupil: [Int] }
struct Spec: Decodable { let sheet: String; let cell_width: Int; let cell_height: Int; let eyes: Eyes; let states: [String: StateSpec] }

let pack = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: pack.appendingPathComponent("character.json")))
let sheet = CGImageSourceCreateImageAtIndex(
    CGImageSourceCreateWithURL(pack.appendingPathComponent(spec.sheet) as CFURL, nil)!, 0, nil)!
let cw = spec.cell_width, ch = spec.cell_height
let bg = CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
let ink = CGColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)

func frame(_ state: String, _ i: Int) -> CGImage {
    let s = spec.states[state]!
    return sheet.cropping(to: CGRect(x: s.frames[i] * cw, y: s.row * ch, width: cw, height: ch))!
}

/// Draws one frame (plus pupils, which the app renders as a separate layer) at `scale`, top-left at (x, yTop).
func drawCat(_ ctx: CGContext, _ state: String, _ i: Int, x: Int, yTop: Int, scale: Int, canvasH: Int) {
    let y = canvasH - yTop - ch * scale
    ctx.interpolationQuality = .none
    ctx.draw(frame(state, i), in: CGRect(x: x, y: y, width: cw * scale, height: ch * scale))
    let s = spec.states[state]!
    guard s.eyes ?? true else { return }
    let off = s.eye_offsets?[i] ?? [0, 0]
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
    for e in [spec.eyes.left, spec.eyes.right] {
        let px = e[0] + off[0], py = e[1] + off[1]
        ctx.fill(CGRect(x: x + px * scale, y: canvasH - yTop - (py + spec.eyes.pupil[1]) * scale,
                        width: spec.eyes.pupil[0] * scale, height: spec.eyes.pupil[1] * scale))
    }
}

func text(_ ctx: CGContext, _ s: String, centerX: CGFloat, y: CGFloat, size: CGFloat) {
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: centerX - CGFloat(w) / 2, y: y)
    CTLineDraw(line, ctx)
}

func context(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(bg)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return c
}

// MARK: Animated demo

let demo: [(String, String, Int)] = [
    ("idle", "hello", 1), ("working", "Claude is thinking", 2), ("needs_you", "Claude needs you", 2),
    ("done", "Claude is done!", 1), ("typing", "kneads while you type", 3), ("overheat", "typing too fast", 4),
    ("listening", "vibing to music", 2), ("petted", "petting = purring", 2), ("paper", "scroll = paper roll", 3),
    ("stretch", "stretch reminder", 1), ("drink", "drink water", 2), ("sleep", "zzz", 1),
]
let scale = 4, W = 420, H = 340
let gifURL = out.appendingPathComponent("demo.gif")
let totalFrames = demo.reduce(0) { $0 + spec.states[$1.0]!.frames.count * $1.2 }
let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, totalFrames, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (state, label, loops) in demo {
    let s = spec.states[state]!
    for _ in 0..<loops {
        for i in 0..<s.frames.count {
            let ctx = context(W, H)
            drawCat(ctx, state, i, x: (W - cw * scale) / 2, yTop: 20, scale: scale, canvasH: H)
            text(ctx, label, centerX: CGFloat(W) / 2, y: 22, size: 18)
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(s.durations_ms[i]) / 1000]]
            CGImageDestinationAddImage(gif, ctx.makeImage()!, props as CFDictionary)
        }
    }
}
precondition(CGImageDestinationFinalize(gif))

// MARK: State grid

let order = ["idle", "working", "needs_you", "done", "typing", "overheat", "listening", "petted",
             "paper", "dragged", "stretch", "drink", "sleep", "peek", "greet"]
let gs = 3, cell = cw * gs, cols = 4, labelH = 34
let rows = (order.count + cols - 1) / cols
let GW = cols * cell, GH = rows * (cell + labelH)
let grid = context(GW, GH)
for (k, state) in order.enumerated() where spec.states[state] != nil {
    let col = k % cols, row = k / cols
    let f = state == "done" ? 2 : state == "stretch" ? 3 : 0
    drawCat(grid, state, min(f, spec.states[state]!.frames.count - 1), x: col * cell, yTop: row * (cell + labelH),
            scale: gs, canvasH: GH)
    text(grid, state.replacingOccurrences(of: "_", with: " "), centerX: CGFloat(col * cell + cell / 2),
         y: CGFloat(GH - (row + 1) * (cell + labelH) + 10), size: 14)
}
let png = CGImageDestinationCreateWithURL(out.appendingPathComponent("states.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(png, grid.makeImage()!, nil)
precondition(CGImageDestinationFinalize(png))
print("Wrote \(gifURL.path) (\(totalFrames) frames) and states.png")
