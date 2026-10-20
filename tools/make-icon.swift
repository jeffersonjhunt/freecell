// Draws Solitaire's app icon with SwiftUI and writes every PNG the asset catalog asks for:
//
//   swift tools/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset [preview-dir]
//
// The artwork uses the app's own colours (the Assets.xcassets colour sets, light appearance): the
// felt table, a blue card back like the game's, and the ace of spades fanned over it.
//   iOS    one 1024 × 1024 opaque square; the system applies the rounded mask.
//   macOS  the same artwork in Apple's macOS icon shape: an 824-pt rounded square with a soft
//          shadow, centred on a transparent 1024 canvas, then scaled to each size.
import AppKit
import SwiftUI

// Colour sets from Assets.xcassets (any appearance).
let tableTop = Color(red: 0.122, green: 0.369, blue: 0.227)
let tableBottom = Color(red: 0.051, green: 0.227, blue: 0.133)
let cardBack = Color(red: 0.114, green: 0.306, blue: 0.612)
let cardRed = Color(red: 0.784, green: 0.063, blue: 0.180)
let cardBlack = Color(red: 0.102, green: 0.102, blue: 0.102)

/// Repeating diagonal lines in both directions — the game's card-back pattern.
struct DiagonalPattern: Shape {
    let spacing: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.maxY)); p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += spacing
        }
        return p
    }
}

struct CardShape: View {
    let width: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
            .fill(.white)
            .frame(width: width, height: width * 1.4)
            .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }
}

struct Back: View {
    let width: CGFloat
    var body: some View {
        let inset = width * 0.07, r = width * 0.09
        CardShape(width: width).overlay {
            RoundedRectangle(cornerRadius: r - inset, style: .continuous)
                .fill(cardBack)
                .overlay(DiagonalPattern(spacing: width * 0.1).stroke(.white.opacity(0.35), lineWidth: width * 0.02))
                .clipShape(RoundedRectangle(cornerRadius: r - inset, style: .continuous))
                .padding(inset)
        }
    }
}

struct Face: View {
    let width: CGFloat
    let rank: String
    let suit: String
    let ink: Color
    /// The big centre pip — off for a card mostly hidden under another, where it would show as a
    /// stray sliver of colour between the two.
    var centre = true
    var body: some View {
        CardShape(width: width).overlay {
            ZStack {
                if centre {
                    Text(suit).font(.system(size: width * 0.62)).foregroundStyle(ink).offset(y: width * 0.06)
                }
                VStack(spacing: -width * 0.05) {
                    Text(rank).font(.system(size: width * 0.27, weight: .bold, design: .rounded))
                    Text(suit).font(.system(size: width * 0.2))
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, width * 0.08).padding(.top, width * 0.05)
            }
        }
    }
}

/// The square artwork, full bleed.
struct Artwork: View {
    var body: some View {
        let w: CGFloat = 430
        ZStack {
            LinearGradient(colors: [tableTop, tableBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.14), .clear], center: .init(x: 0.5, y: 0.38),
                           startRadius: 0, endRadius: 560)
            Back(width: w).rotationEffect(.degrees(-15)).offset(x: -130, y: 24)
            Face(width: w, rank: "K", suit: "♥", ink: cardRed, centre: false).rotationEffect(.degrees(-2)).offset(x: 0, y: 0)
            Face(width: w, rank: "A", suit: "♠", ink: cardBlack).rotationEffect(.degrees(13)).offset(x: 138, y: 34)
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }
}

/// macOS: Apple's icon grid — an 824 × 824 rounded square (corner 185) centred, with a drop shadow.
struct MacIcon: View {
    var body: some View {
        Artwork()
            .scaleEffect(824.0 / 1024.0)
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            .frame(width: 1024, height: 1024)
    }
}

@MainActor func render<V: View>(_ view: V) -> CGImage {
    let r = ImageRenderer(content: view)
    r.scale = 1
    guard let image = r.cgImage else { fatalError("render failed") }
    return image
}

/// Redraws `image` at `size` × `size`; `opaque` drops the alpha channel (the App Store rejects an
/// iOS icon with one).
func resized(_ image: CGImage, _ size: Int, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: swift tools/make-icon.swift <AppIcon.appiconset> [preview-dir]"); exit(2) }
let out = URL(fileURLWithPath: args[1])

MainActor.assumeIsolated {
    let ios = render(Artwork())
    let mac = render(MacIcon())
    writePNG(resized(ios, 1024, opaque: true), out.appendingPathComponent("icon-ios-1024.png"))
    // The About screen shows the same artwork (an imageset beside the app icon set).
    let about = out.deletingLastPathComponent().appendingPathComponent("AboutIcon.imageset")
    if FileManager.default.fileExists(atPath: about.path) {
        writePNG(resized(ios, 1024, opaque: true), about.appendingPathComponent("about-icon.png"))
    }
    var images: [[String: String]] = [
        ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-ios-1024.png"],
    ]
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = points * scale
            let name = "icon-mac-\(px).png"
            if !FileManager.default.fileExists(atPath: out.appendingPathComponent(name).path) {
                writePNG(resized(mac, px, opaque: false), out.appendingPathComponent(name))
            }
            images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try! json.write(to: out.appendingPathComponent("Contents.json"))
    if args.count >= 3 {
        let preview = URL(fileURLWithPath: args[2])
        writePNG(resized(ios, 1024, opaque: true), preview.appendingPathComponent("Solitaire-icon-ios.png"))
        writePNG(resized(mac, 1024, opaque: false), preview.appendingPathComponent("Solitaire-icon-mac.png"))
    }
    print("wrote \(images.count) icon images to \(out.path)")
}
