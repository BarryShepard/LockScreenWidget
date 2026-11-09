import AppKit

@main struct SceneTests {
    static func check(_ condition: Bool, _ message: String = "Scene assertion failed") {
        assert(condition, message)
    }

    static func expectFailure(_ action: () throws -> Void) {
        do {
            try action()
            fatalError("Invalid scene or image was accepted")
        } catch {
            assert(error.localizedDescription.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil,
                   "Scene and image errors must be readable in Russian: \(error)")
        }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SceneStore(directory: directory)
        check(try store.load() == nil)

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pixels = bitmap.bitmapData!
        pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        for x in 0..<2 {
            for y in 0..<2 {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = 255
                pixels[offset + 3] = 255
            }
        }
        let imageData = bitmap.representation(using: .png, properties: [:])!
        let sourceURL = directory.appendingPathComponent("original.png")
        try imageData.write(to: sourceURL)
        let assetID = try store.importImage(at: sourceURL)
        try FileManager.default.removeItem(at: sourceURL)
        let importedURL = store.imageURL(for: assetID)!
        check(try Data(contentsOf: importedURL) == imageData, "Imports must retain original bytes")
        assert(store.image(for: assetID)?.isValid == true, "Deleting the source must not affect the import")
        let secondAssetID = try store.importImage(data: imageData)
        assert(assetID != secondAssetID, "Each import must have a unique identity")
        expectFailure { _ = try store.importImage(data: Data("not an image".utf8)) }
        expectFailure { _ = try store.importImage(data: Data()) }
        expectFailure { _ = try store.importImage(at: sourceURL) }

        var text = SceneElement(kind: .text, frame: CGRect(x: 20, y: 30, width: 300, height: 100))
        text.text = "Личный экран\nВторая строка"
        text.name = "Заголовок"
        text.rotation = -15.5
        text.cornerRadius = 8
        text.opacity = 0.75
        text.style = SceneTextStyle(family: "Missing Font For Scene Test", weight: 6, fontSize: 42,
                                    lineHeight: 58, letterSpacing: -2.5,
                                    horizontalAlignment: 2, verticalAlignment: 1,
                                    color: SceneColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
        var image = SceneElement(kind: .image, frame: CGRect(x: -10, y: 220, width: 200, height: 150),
                                 assetID: assetID, imageRect: CGRect(x: -30, y: 0, width: 300, height: 150))
        var secondText = SceneElement(kind: .text, frame: CGRect(x: 70, y: 450, width: 100, height: 60))
        secondText.style.fontSize = 18
        let scene = EditorScene(canvasSize: CGSize(width: 1512, height: 982), elements: [text, image, secondText])
        try store.save(scene)
        check(try store.load() == scene, "Geometry, text style, order, and image references must round trip")
        let reopened = try SceneStore(directory: directory)
        check(try reopened.load() == scene)
        assert(reopened.image(for: assetID)?.isValid == true)
        assert(abs(text.style.font(scale: 0.5).pointSize - 21) < 0.001)
        assert(text.style.family == "Missing Font For Scene Test", "Font fallback must preserve the stored family")
        let color = text.style.color.nsColor.usingColorSpace(.sRGB)!
        assert(abs(color.redComponent - 0.2) < 0.001 && abs(color.alphaComponent - 0.8) < 0.001)
        assert(scene.elements[2].style.fontSize == 18, "Block styles must remain independent")

        for unsafe in ["../scene.json", "..", ".", "", "/tmp/test", "folder/file", "folder\\file", "%2e%2e", "a\0b"] {
            assert(store.imageURL(for: unsafe) == nil)
            assert(store.image(for: unsafe) == nil)
        }
        let linkID = "external-image"
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("Assets/\(linkID)"),
                                                  withDestinationURL: importedURL)
        assert(store.imageURL(for: linkID) == nil, "Asset resolution must not follow symbolic links")
        assert(store.imageURL(for: "missing-image") == nil)
        image.assetID = "missing-image"
        let missingImageScene = EditorScene(canvasSize: scene.canvasSize, elements: [image])
        try store.save(missingImageScene)
        check(try store.load() == missingImageScene, "Missing assets must remain representable")
        assert(store.image(for: assetID)?.isValid == true, "Saving must retain old assets for Undo")
        try store.save(scene)

        let documentURL = directory.appendingPathComponent("scene.json")
        let savedBytes = try Data(contentsOf: documentURL)
        func reject(_ edit: (inout EditorScene) -> Void) throws {
            var invalid = scene
            edit(&invalid)
            expectFailure { try store.save(invalid) }
            check(try Data(contentsOf: documentURL) == savedBytes, "Failed saves must preserve the previous file")
            check(try store.load() == scene)
        }
        try reject { $0.schemaVersion = 2 }
        try reject { $0.canvasSize.width = 0 }
        try reject { $0.canvasSize.height = .infinity }
        try reject { $0.elements.append($0.elements[0]) }
        try reject { $0.elements[0].frame.size.width = .nan }
        try reject { $0.elements[0].frame.size.height = -1 }
        try reject { $0.elements[0].frame.origin.x = .infinity }
        try reject { $0.elements[0].rotation = .nan }
        try reject { $0.elements[0].cornerRadius = -1 }
        try reject { $0.elements[0].opacity = 1.1 }
        try reject { $0.elements[1].imageRect = CGRect(x: 0, y: 0, width: 0, height: 1) }
        try reject { $0.elements[1].assetID = "../scene.json" }
        try reject { $0.elements[0].style.family = " " }
        try reject { $0.elements[0].style.weight = 9 }
        try reject { $0.elements[0].style.fontSize = 0 }
        try reject { $0.elements[0].style.fontSize = .infinity }
        try reject { $0.elements[0].style.lineHeight = -1 }
        try reject { $0.elements[0].style.letterSpacing = .nan }
        try reject { $0.elements[0].style.horizontalAlignment = 3 }
        try reject { $0.elements[0].style.verticalAlignment = -1 }
        try reject { $0.elements[0].style.color.red = 1.1 }
        try reject { $0.elements[0].style.color.alpha = .nan }

        try Data("not JSON".utf8).write(to: documentURL)
        expectFailure { _ = try store.load() }
        check(try Data(contentsOf: documentURL) == Data("not JSON".utf8), "Loading corruption must never reset it")
        var invalidVersion = scene
        invalidVersion.schemaVersion = 100
        try JSONEncoder().encode(invalidVersion).write(to: documentURL)
        expectFailure { _ = try store.load() }
        var invalidGeometry = scene
        invalidGeometry.elements[0].frame.size.width = -3
        try JSONEncoder().encode(invalidGeometry).write(to: documentURL)
        expectFailure { _ = try store.load() }
        try FileManager.default.removeItem(at: documentURL)
        try FileManager.default.createSymbolicLink(at: documentURL, withDestinationURL: sourceURL)
        expectFailure { _ = try store.load() }

        print("Scene checks passed: style/geometry round trip, font fallback, independent styles, schema and numeric validation.")
        print("Store checks passed: durable original image bytes, unique imports, safe IDs, missing assets, atomic save preservation, corrupt document errors.")
    }
}
