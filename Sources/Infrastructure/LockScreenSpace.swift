// Adapted from Lakr233/SkyLightWindow, revision b7bd99f (MIT).
// Copyright (c) 2025 Lakr Aream. See Resources/Licenses/SkyLightWindow-MIT.txt.
import AppKit
import Darwin

/// Experimental WindowServer space, above the screen-lock space (300).
/// No authentication, input handling, or persistent system settings are changed.
protocol LockScreenSpaceManaging: AnyObject {
    func attach(_ window: NSWindow) -> Bool
    func tearDown()
}

final class LockScreenSpace: LockScreenSpaceManaging {
    private(set) static var lastFailure = ""
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    // Show/hide are void in the WindowServer headers used by yabai.
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Void
    private typealias Add = @convention(c) (Int32, Int32, CFArray, Int32) -> Void
    private typealias Remove = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias Destroy = @convention(c) (Int32, Int32) -> Void

    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: Int32
    private let show: Spaces
    private let add: Add
    private let remove: Remove
    private let hide: Spaces
    private let destroy: Destroy
    private var windowNumbers: Set<Int> = []
    private var active = true

    init?() {
        Self.lastFailure = ""
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else { Self.lastFailure = "dlopen"; return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { Self.lastFailure = "symbol: \(name)"; return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let main = symbol("SLSMainConnectionID", Connection.self),
              let create = symbol("SLSSpaceCreate", Create.self),
              let level = symbol("SLSSpaceSetAbsoluteLevel", SetLevel.self),
              let show = symbol("SLSShowSpaces", Spaces.self),
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", Add.self),
              let remove = symbol("SLSRemoveWindowsFromSpaces", Remove.self),
              let hide = symbol("SLSHideSpaces", Spaces.self),
              let destroy = symbol("SLSSpaceDestroy", Destroy.self) else {
            dlclose(handle)
            return nil
        }
        let connection = main()
        let space = create(connection, 1, 0)
        guard space > 0 else { Self.lastFailure = "create: connection=\(connection) space=\(space)"; dlclose(handle); return nil }
        // 400 is the notification-center-at-screen-lock space level used upstream.
        let levelResult = level(connection, space, 400)
        guard levelResult == 0 else {
            Self.lastFailure = "setup: level=\(levelResult)"
            destroy(connection, space)
            dlclose(handle)
            return nil
        }
        show(connection, [NSNumber(value: space)] as CFArray)
        self.handle = handle
        self.connection = connection
        self.space = space
        self.show = show
        self.add = add
        self.remove = remove
        self.hide = hide
        self.destroy = destroy
    }

    func attach(_ window: NSWindow) -> Bool {
        guard active, window.windowNumber > 0 else { Self.lastFailure = "attach: no window number"; return false }
        let number = window.windowNumber
        show(connection, [NSNumber(value: space)] as CFArray)
        let windows = [NSNumber(value: number)] as CFArray
        // Managed-space queries omit this private space; they cannot verify the move.
        add(connection, space, windows, 7)
        windowNumbers.insert(number)
        return true
    }

    func tearDown() {
        guard active else { return }
        active = false
        let spaces = [NSNumber(value: space)] as CFArray
        if !windowNumbers.isEmpty {
            remove(connection, windowNumbers.map { NSNumber(value: $0) } as CFArray, spaces)
        }
        hide(connection, spaces)
        destroy(connection, space)
        windowNumbers.removeAll()
    }

    deinit { tearDown(); dlclose(handle) }
}
