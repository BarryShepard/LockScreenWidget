import AppKit

@main struct GenerateIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let source = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
            throw NSError(domain: "Mice.Icon", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected destination iconset and source PNG"])
        }
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
                NSGraphicsContext.current?.imageInterpolation = .high
                let scale = NSAffineTransform()
                scale.scale(by: CGFloat(pixels) / 1024)
                scale.concat()
                source.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                            from: .zero, operation: .copy, fraction: 1)
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
