import AppKit

@main struct GenerateIcon {
    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var chunks = Data()
        let iconTypes = [16: "icp4", 32: "icp5", 64: "icp6", 128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"]
        var included: Set<Int> = []
        func length(_ value: Int) -> Data {
            var encoded = UInt32(value).bigEndian
            return withUnsafeBytes(of: &encoded) { Data($0) }
        }
        for points in [16, 32, 128, 256, 512] {
            for density in [1, 2] {
                let pixels = points * density
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let scale = NSAffineTransform()
                scale.scale(by: CGFloat(pixels) / 1024)
                scale.concat()
                let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                              xRadius: 200, yRadius: 200)
                NSGradient(starting: NSColor(srgbRed: 0.035, green: 0.035, blue: 0.043, alpha: 1),
                           ending: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1))!.draw(in: background, angle: 90)
                let skull = StatusIcon.path()
                let position = NSAffineTransform()
                position.translateX(by: 152, yBy: 152)
                position.scale(by: 40)
                skull.transform(using: position as AffineTransform)
                NSColor(srgbRed: 0.94, green: 0.90, blue: 0.83, alpha: 1).setFill()
                skull.fill()
                NSGraphicsContext.restoreGraphicsState()
                let suffix = density == 2 ? "@2x" : ""
                let file = destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: file)
                if included.insert(pixels).inserted, let type = iconTypes[pixels] {
                    chunks.append(Data(type.utf8))
                    chunks.append(length(png.count + 8))
                    chunks.append(png)
                }
            }
        }
        var icns = Data("icns".utf8)
        icns.append(length(chunks.count + 8))
        icns.append(chunks)
        try icns.write(to: destination.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
    }
}
