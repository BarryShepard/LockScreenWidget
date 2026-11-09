import Foundation

func logDiagnostic(_ message: String) {
    guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
    let directory = library.appendingPathComponent("Logs/TEotW", isDirectory: true)
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return }
    let url = directory.appendingPathComponent("diagnostics.log")
    let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
    if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url); return }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    do { try handle.seekToEnd(); try handle.write(contentsOf: data) } catch { }
}
