import Foundation

final class MemoryPreferences: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
