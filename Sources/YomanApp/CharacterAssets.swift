import AppKit
import ImageIO
import YomanCore

/// A loaded character pack: frames cut from the sheet, plus an alpha mask per frame for click-through hit tests.
final class CharacterAssets {
    struct Frame {
        let image: CGImage
        /// Row-major, top row first; true where the pixel is opaque.
        let mask: [Bool]
    }

    let spec: CharacterSpec
    let frames: [String: [Frame]]
    let pupilColor: CGColor

    init(dir: URL) throws {
        let spec = try CharacterSpec.load(from: dir)
        let issues = spec.validate()
        guard issues.isEmpty else {
            throw NSError(domain: "Yoman", code: 1, userInfo: [NSLocalizedDescriptionKey: issues.joined(separator: "; ")])
        }
        let url = dir.appendingPathComponent(spec.sheet)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw NSError(domain: "Yoman", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot read \(url.path)"]) }

        let w = spec.cellWidth, h = spec.cellHeight
        var out: [String: [Frame]] = [:]
        for (name, state) in spec.states {
            out[name] = state.frames.compactMap { col in
                let rect = CGRect(x: col * w, y: state.row * h, width: w, height: h)
                guard let img = sheet.cropping(to: rect) else { return nil }
                return Frame(image: img, mask: Self.alphaMask(img))
            }
        }
        self.spec = spec
        self.frames = out
        self.pupilColor = Self.color(spec.eyes?.color ?? "#222222")
    }

    static func alphaMask(_ img: CGImage) -> [Bool] {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Array(repeating: true, count: w * h) }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<(w * h)).map { px[$0 * 4 + 3] > 127 }
    }

    static func color(_ hex: String) -> CGColor {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Bundled pack, or `YOMAN_CHARACTER_DIR` for development.
    static func defaultDirectory() -> URL? {
        if let dev = ProcessInfo.processInfo.environment["YOMAN_CHARACTER_DIR"] {
            return URL(fileURLWithPath: dev)
        }
        let custom = YomanPaths.supportDir.appendingPathComponent("character")
        if FileManager.default.fileExists(atPath: custom.appendingPathComponent("character.json").path) {
            return custom
        }
        return Bundle.main.resourceURL?.appendingPathComponent("characters/cat")
    }
}
