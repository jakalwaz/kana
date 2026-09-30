// Draws Kana's mark, カナ, as the source shape for the app icon: カ in mauve,
// ナ in Kana red, heavy Hiragino on black. image_to_kana.py turns it into
// tiles and render_icon.swift into the icon (tools/icon/make_icon.sh).
//
//   swift tools/icon/draw_mark.swift <out.png>

import AppKit

let size = NSSize(width: 1400, height: 800)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.black.setFill()
NSRect(origin: .zero, size: size).fill()

let font = NSFont(name: "HiraginoSans-W8", size: 620) ?? .boldSystemFont(ofSize: 620)
let mauve = NSColor(srgbRed: 0.66, green: 0.59, blue: 0.64, alpha: 1)
let red = NSColor(srgbRed: 0.88, green: 0.15, blue: 0.18, alpha: 1) // #e0262f, Kana's accent
let text = NSMutableAttributedString(string: "カ", attributes: [.font: font, .foregroundColor: mauve])
text.append(NSAttributedString(string: "ナ", attributes: [.font: font, .foregroundColor: red]))
let t = text.size()
text.draw(at: NSPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2))

try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
