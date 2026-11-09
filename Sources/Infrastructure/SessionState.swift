import CoreGraphics
import Foundation

func readSessionLockState() -> Bool? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    // The dictionary key is undocumented. Fail closed unless the session is ours and active.
    guard let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool, onConsole else { return false }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}
