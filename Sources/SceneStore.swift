import AppKit
import Darwin
import zlib

final class SceneStore {
    private let documentURL: URL
    private let assetsURL: URL
    private let assetsDevice: dev_t
    private let assetsInode: ino_t
    private let fileManager = FileManager.default

    init(directory: URL) throws {
        documentURL = directory.appendingPathComponent("scene.json", isDirectory: false)
        assetsURL = directory.appendingPathComponent("Assets", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // mkdir does not follow an existing Assets symbolic link.
            if mkdir(assetsURL.path, S_IRWXU) != 0 && errno != EEXIST {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            throw SceneError.storage("Не удалось создать папку документа и изображений.", error)
        }
        let descriptor = try Self.openAssetsDirectory(at: assetsURL)
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw SceneError.invalid("Не удалось проверить папку изображений документа.")
        }
        assetsDevice = info.st_dev
        assetsInode = info.st_ino
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

    /// Remove only the first, provisional typing save that this editor made.
    func discardProvisionalDocument(matching expected: EditorScene) throws {
        guard let current = try load() else { return }
        guard current == expected else {
            throw SceneError.invalid("Документ изменился. Отмена ввода не удалила сохранённый файл.")
        }
        guard unlink(documentURL.path) == 0 || errno == ENOENT else {
            throw SceneError.storage("Не удалось удалить временно сохранённый документ.", POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
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
        try importImages(data: [data])[0].assetID
    }

    func importImages(data: [Data]) throws -> [(assetID: String, size: CGSize)] {
        // Validate the entire batch before allocating its first asset.
        let sizes = try data.map(Self.imageSize)
        let directory = try assetsDirectoryDescriptor()
        defer { close(directory) }
        var assets: [(assetID: String, size: CGSize)] = []
        do {
            for (bytes, size) in zip(data, sizes) {
                assets.append((try writeAsset(bytes, in: directory), size))
            }
        } catch {
            for asset in assets { unlinkat(directory, asset.assetID, 0) }
            throw error
        }
        return assets
    }

    private static func imageSize(_ data: Data) throws -> CGSize {
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard (!data.starts(with: pngSignature) || hasCompletePNGChunks(data)),
              let image = NSImage(data: data), image.isValid,
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw SceneError.invalid("Не удалось открыть изображение: файл повреждён или его формат не поддерживается.")
        }
        return image.size
    }

    // AppKit recovers a partial IDAT as a valid bitmap. Walk the length-delimited
    // chunks through IEND and check each CRC before letting AppKit use the image.
    private static func hasCompletePNGChunks(_ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 8 // PNG signature
            while bytes.count - offset >= 12 {
                let length = Int(UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                guard length <= bytes.count - offset - 12 else { return false }
                let type = UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                let checksum = UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 8 + length, as: UInt32.self))
                let chunk = bytes.baseAddress!.advanced(by: offset + 4).assumingMemoryBound(to: UInt8.self)
                guard length <= Int(Int32.max), crc32(0, chunk, UInt32(4 + length)) == checksum else { return false }
                if type == 0x49454E44 { return length == 0 } // IEND
                offset += 12 + length
            }
            return false
        }
    }

    private func writeAsset(_ data: Data, in directory: Int32) throws -> String {
        let assetID = UUID().uuidString
        let descriptor = openat(directory, assetID, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SceneError.invalid("Не удалось создать копию изображения в документе.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            unlinkat(directory, assetID, 0)
            throw SceneError.storage("Не удалось сохранить копию изображения в документе.", error)
        }
        return assetID
    }

    func imageURL(for assetID: String) -> URL? {
        guard let descriptor = imageDescriptor(for: assetID) else { return nil }
        defer { close(descriptor) }
        return assetsURL.appendingPathComponent(assetID, isDirectory: false)
    }

    func image(for assetID: String) -> NSImage? {
        guard let descriptor = imageDescriptor(for: assetID) else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(), let image = NSImage(data: data), image.isValid else {
            return nil
        }
        return image
    }

    private static func openAssetsDirectory(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw SceneError.invalid("Папка изображений должна быть обычной папкой, а не символической ссылкой.")
        }
        return descriptor
    }

    private func assetsDirectoryDescriptor() throws -> Int32 {
        let descriptor = try Self.openAssetsDirectory(at: assetsURL)
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_dev == assetsDevice, info.st_ino == assetsInode else {
            close(descriptor)
            throw SceneError.invalid("Папка изображений документа была заменена. Откройте документ заново.")
        }
        return descriptor
    }

    private func imageDescriptor(for assetID: String) -> Int32? {
        guard EditorScene.isSafeAssetID(assetID), let directory = try? assetsDirectoryDescriptor() else {
            return nil
        }
        defer { close(directory) }
        let descriptor = openat(directory, assetID, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            return nil
        }
        return descriptor
    }
}
