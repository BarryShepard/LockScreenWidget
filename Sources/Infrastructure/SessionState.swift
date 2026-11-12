import CoreGraphics
import Foundation

enum LockSessionState: String {
    case locked, unlocked, inactive, activeWithoutLockFlag, unknown
}

func decodeSessionState(_ session: [String: Any]?) -> LockSessionState {
    guard let session else { return .unknown }
    guard let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool else { return .unknown }
    guard onConsole else { return .inactive }
    guard let value = session["CGSSessionScreenIsLocked"] else { return .activeWithoutLockFlag }
    guard let locked = value as? Bool else { return .unknown }
    return locked ? .locked : .unlocked
}

func readSessionLockState() -> LockSessionState {
    decodeSessionState(CGSessionCopyCurrentDictionary() as? [String: Any])
}
