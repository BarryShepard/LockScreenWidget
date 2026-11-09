import AppKit

final class SceneStore {
    private let documentURL: URL
    private let assetsURL: URL
    private let fileManager = FileManager.default

    init(directory: URL) throws {
        documentURL = directory.appendingPathComponent("scene.json", isDirectory: false)
        assetsURL = directory.appendingPathComponent("Assets", isDirectory: true)
        do {
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        } catch {
            throw SceneError.storage("Не удалось создать папку документа и изображений.", error)
        }
    }

    static func defaultDirectory() throws -> URL {
        do {
            return try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LockScreenWidget", isDirectory: true)
        } catch {
            throw SceneError.storage("Не удалось найти папку Application Support для документа.", error)
        }
    }

    func load() throws -> EditorScene? {
        let data: Data
        do {
            data = try Data(contentsOf: documentURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A dangling symbolic link is an existing, unreadable document.
            if (try? fileManager.destinationOfSymbolicLink(atPath: documentURL.path)) == nil {
                return nil
            }
            throw SceneError.storage("Не удалось прочитать сохранённый документ.", error)
        } catch {
            throw SceneError.storage("Не удалось прочитать сохранённый документ.", error)
        }
        do {
            return try JSONDecoder().decode(EditorScene.self, from: data).validated()
        } catch let error as SceneError {
            throw error
        } catch {
            throw SceneError.storage("Сохранённый документ повреждён: не удалось прочитать его содержимое.", error)
        }
    }

    func save(_ scene: EditorScene) throws {
        let validated = try scene.validated()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(validated)
            _ = try JSONDecoder().decode(EditorScene.self, from: data).validated()
            try data.write(to: documentURL, options: .atomic)
        } catch {
            throw SceneError.storage("Не удалось сохранить документ. Предыдущий файл сохранён.", error)
        }
    }

    func importImage(at url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SceneError.storage("Не удалось прочитать исходное изображение «\(url.lastPathComponent)».", error)
        }
        return try importImage(data: data)
    }

    func importImage(data: Data) throws -> String {
        guard let image = NSImage(data: data), image.isValid,
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw SceneError.invalid("Не удалось открыть изображение: файл повреждён или его формат не поддерживается.")
        }
        let assetID = UUID().uuidString
        do {
            try data.write(to: assetsURL.appendingPathComponent(assetID), options: .atomic)
        } catch {
            throw SceneError.storage("Не удалось сохранить копию изображения в документе.", error)
        }
        return assetID
    }

    func imageURL(for assetID: String) -> URL? {
        guard EditorScene.isSafeAssetID(assetID) else { return nil }
        let url = assetsURL.appendingPathComponent(assetID, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }

    func image(for assetID: String) -> NSImage? {
        guard let url = imageURL(for: assetID), let image = NSImage(contentsOf: url), image.isValid else {
            return nil
        }
        return image
    }
}
