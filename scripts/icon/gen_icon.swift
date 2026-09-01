// Generates mdNotch's app icon as an .iconset, in the same visual language
// as the notch drop zone: a black slab hanging from the top, lit from behind
// by a rotating spectrum glow.
//
// The arrow is drawn by hand rather than taken from SF Symbols: Apple's
// license permits those in an app's interface but not in app icons or logos.
//
// Usage:
//   swiftc -parse-as-library gen_icon.swift -o gen_icon && ./gen_icon <out.iconset>

import SwiftUI
import AppKit

/// One icon, sized in points; every metric is a fraction of the canvas so
/// each rendered size is identical, not a resample of a bigger one.
struct IconView: View {
    let canvas: CGFloat

    private var side: CGFloat { canvas * 0.82 }
    private var slabWidth: CGFloat { side * 0.44 }
    private var slabHeight: CGFloat { side * 0.21 }

    private static let spectrum: [Color] = [
        Color(red: 0.35, green: 0.55, blue: 1.00),
        Color(red: 0.68, green: 0.42, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.74),
        Color(red: 1.00, green: 0.66, blue: 0.38),
        Color(red: 0.35, green: 0.55, blue: 1.00),
    ]

    var body: some View {
        let gradient = AngularGradient(colors: Self.spectrum, center: .center, angle: .degrees(-35))
        let slabShape = UnevenRoundedRectangle(
            bottomLeadingRadius: slabWidth * 0.17,
            bottomTrailingRadius: slabWidth * 0.17,
            style: .continuous
        )

        let body = RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)

        ZStack {
            body
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.17), Color(white: 0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // The notch, hanging from the top edge and lit from behind.
            // Clipped to the body so nothing escapes the icon's silhouette.
            ZStack {
                slabShape
                    .stroke(gradient, lineWidth: slabWidth * 0.30)
                    .blur(radius: slabWidth * 0.26)
                    .opacity(0.9)
                slabShape
                    .stroke(gradient, lineWidth: slabWidth * 0.10)
                    .blur(radius: slabWidth * 0.07)
                slabShape
                    .stroke(gradient, lineWidth: max(slabWidth * 0.020, 0.5))
                    .blur(radius: max(slabWidth * 0.010, 0.3))

                slabShape.fill(.black)
            }
            .frame(width: slabWidth, height: slabHeight)
            .offset(y: -(side - slabHeight) / 2)
            .frame(width: side, height: side)
            .clipShape(body)

            DownArrow()
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: side * 0.055,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: side * 0.30, height: side * 0.30)
                .offset(y: side * 0.10)

            body.strokeBorder(.white.opacity(0.10), lineWidth: max(canvas * 0.004, 0.5))
        }
        .frame(width: side, height: side)
        .frame(width: canvas, height: canvas)
    }
}

/// Stem plus chevron, drawn rather than borrowed from a system symbol.
private struct DownArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let head = rect.width * 0.5

        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY))

        path.move(to: CGPoint(x: midX - head, y: rect.maxY - head))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: midX + head, y: rect.maxY - head))
        return path
    }
}

@main
struct Main {
    /// (pixel size, file name) pairs macOS expects in an .iconset.
    static let variants: [(CGFloat, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            print("usage: gen_icon <out.iconset>", to: &StandardError.shared)
            exit(2)
        }
        let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        MainActor.assumeIsolated {
            for (size, name) in variants {
                let renderer = ImageRenderer(content: IconView(canvas: size))
                renderer.scale = 1
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    print("failed: \(name)")
                    continue
                }
                try? png.write(to: outDir.appendingPathComponent(name))
            }
        }
        print("wrote \(variants.count) sizes to \(outDir.path)")
    }
}

/// Minimal stderr sink so usage errors don't go to stdout.
struct StandardError: TextOutputStream {
    static var shared = StandardError()
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
