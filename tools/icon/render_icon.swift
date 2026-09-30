// Renders one frame of a .kana clip as a macOS app icon: each character in a
// small rounded tile, tinted by its colour, on a dark rounded square with a
// faint disc behind. 1024×1024 PNG, on Apple's icon grid (824 pt body).
//
//   swift tools/icon/render_icon.swift <clip.kana> <out.png> [frame] [palette]
//
// frame defaults to the clip's portrait frame (negative counts from the end).
// palette: `mauve` (default), `red`, or `source` (each cell's own colour, for
// shapes drawn in chosen colours, like the カナ mark). Tiles are one colour, lighter where the
// character is denser; only the few most vivid cells get the accent (red on
// mauve, white on red), like a highlight. Lone specks are dropped so the
// shape reads cleanly. No dependencies beyond AppKit.

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render_icon.swift <clip.kana> <out.png> [frame] [tint]\n".utf8))
    exit(2)
}

struct Clip: Decodable {
    struct Frame: Decodable { let rows: [String]; let colors: String? }
    let width: Int, height: Int, portrait: Int, frames: [Frame]
}

let clip = try JSONDecoder().decode(Clip.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
guard !clip.frames.isEmpty else { fatalError("the clip has no frames") }
var index = args.count > 3 ? Int(args[3]) ?? clip.portrait : clip.portrait
if index < 0 { index += clip.frames.count }
let frame = clip.frames[max(0, min(clip.frames.count - 1, index))]
let palette = args.count > 4 ? args[4] : "mauve"
var rows = frame.rows.map { Array($0) }
// colours only when there's one per cell, as the .kana format says
let colors = frame.colors.flatMap { Data(base64Encoded: $0) }.map { [UInt8]($0) }
    .flatMap { $0.count == clip.width * clip.height * 3 ? $0 : nil }

// Drop specks: cells with fewer than two lit neighbours.
func isLit(_ x: Int, _ y: Int) -> Bool { rows.indices.contains(y) && rows[y].indices.contains(x) && rows[y][x] != " " }
let lone = rows.indices.flatMap { y in rows[y].indices.filter { x in
    isLit(x, y) && [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        .filter { isLit(x + $0.0, y + $0.1) }.count < 2
}.map { (x: $0, y: y) } }
for cell in lone { rows[cell.y][cell.x] = " " }

// Character density, 0...1, by the converter's ramp (darkest to brightest).
let ramp = Array(" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$")
func density(_ c: Character) -> CGFloat {
    CGFloat(ramp.firstIndex(of: c) ?? ramp.count / 2) / CGFloat(ramp.count - 1)
}
// The accent goes to the most vivid ~4% of cells.
func vividness(_ x: Int, _ y: Int) -> CGFloat {
    guard let colors else { return 0 }
    let i = (y * clip.width + x) * 3
    let (r, g, b) = (CGFloat(colors[i]), CGFloat(colors[i + 1]), CGFloat(colors[i + 2]))
    let hi = max(r, g, b) / 255, lo = min(r, g, b) / 255
    // bright and either saturated (a light) or near white (a highlight)
    return hi * (palette == "red" ? (1 - (hi - lo)) * hi : hi - lo)
}

// Trim blank rows and columns so the subject fills the icon.
let lit = rows.indices.flatMap { y in rows[y].indices.compactMap { x in rows[y][x] == " " ? nil : (x, y) } }
guard let minX = lit.map(\.0).min(), let maxX = lit.map(\.0).max(),
      let minY = lit.map(\.1).min(), let maxY = lit.map(\.1).max()
else { fatalError("the frame is blank") }
let cols = maxX - minX + 1, lines = maxY - minY + 1

let size: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824) // Apple's macOS icon grid
let radius: CGFloat = 185

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: size) // draw top-down, like the grid
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// body: a soft shadow, the two-tone dark square, a hairline edge
let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: rgb(0, 0, 0, 0.45))
ctx.addPath(shape); ctx.setFillColor(rgb(0.13, 0.125, 0.14)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
ctx.setFillColor(rgb(0.165, 0.16, 0.175)); ctx.fill(CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2))
// the disc
let disc = body.width * 0.43
ctx.setFillColor(rgb(1, 1, 1, 0.045))
ctx.fillEllipse(in: CGRect(x: body.midX - disc, y: body.midY - disc, width: disc * 2, height: disc * 2))
ctx.restoreGState()
ctx.addPath(shape); ctx.setStrokeColor(rgb(1, 1, 1, 0.12)); ctx.setLineWidth(2); ctx.strokePath()

// the grid: cells a little taller than wide (0.83), fitted inside the body
let pad = body.width * 0.07
let cellW = min((body.width - 2 * pad) / CGFloat(cols), (body.height - 2 * pad) * 0.83 / CGFloat(lines))
let cellH = cellW / 0.83
let origin = CGPoint(x: body.midX - cellW * CGFloat(cols) / 2, y: body.midY - cellH * CGFloat(lines) / 2)
let font = NSFont.monospacedSystemFont(ofSize: cellH * 0.78, weight: .bold)
let litCells = (minY ... maxY).flatMap { y in (minX ... maxX).filter { isLit($0, y) }.map { (x: $0, y: y) } }
let vivid = litCells.map { vividness($0.x, $0.y) }.sorted()
let accentFrom = vivid.isEmpty ? 2 : vivid[Int(Double(vivid.count - 1) * 0.96)]
let base: (r: CGFloat, g: CGFloat, b: CGFloat) = palette == "red" ? (0.72, 0.14, 0.18) : (0.62, 0.55, 0.60)
let accent: (r: CGFloat, g: CGFloat, b: CGFloat) = palette == "red" ? (0.95, 0.93, 0.94) : (0.88, 0.15, 0.18)

for y in minY ... maxY {
    for x in minX ... maxX where isLit(x, y) {
        // one colour, a little lighter where the character is denser
        let shade = 0.78 + 0.3 * density(rows[y][x])
        var (r, g, b) = (base.r * shade, base.g * shade, base.b * shade)
        if palette == "source", let colors {
            let i = (y * clip.width + x) * 3
            let tone = 0.82 + 0.25 * density(rows[y][x])
            (r, g, b) = (min(1, CGFloat(colors[i]) / 255 * tone), min(1, CGFloat(colors[i + 1]) / 255 * tone),
                         min(1, CGFloat(colors[i + 2]) / 255 * tone))
        } else if vividness(x, y) >= accentFrom, vividness(x, y) > 0.35 {
            (r, g, b) = accent
        }
        let cell = CGRect(x: origin.x + CGFloat(x - minX) * cellW, y: origin.y + CGFloat(y - minY) * cellH,
                          width: cellW, height: cellH).insetBy(dx: cellW * 0.06, dy: cellH * 0.06)
        ctx.setFillColor(rgb(r, g, b, 0.9))
        ctx.addPath(CGPath(roundedRect: cell, cornerWidth: cellW * 0.16, cornerHeight: cellW * 0.16, transform: nil))
        ctx.fillPath()
        // the character, a shade lighter than its tile
        let ink = NSColor(srgbRed: min(1, r + 0.22), green: min(1, g + 0.22), blue: min(1, b + 0.22), alpha: 1)
        let text = NSAttributedString(string: String(rows[y][x]), attributes: [.font: font, .foregroundColor: ink])
        let t = text.size()
        ctx.saveGState()
        ctx.translateBy(x: cell.midX - t.width / 2, y: cell.midY + t.height / 2)
        ctx.scaleBy(x: 1, y: -1) // text wants y up
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: .zero)
        ctx.restoreGState()
    }
}

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) (\(cols)×\(lines) cells, frame \(index))")
