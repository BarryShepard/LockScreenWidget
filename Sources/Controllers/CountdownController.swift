import Foundation

/// The only repeating timer. Both interfaces receive exactly the same instant.
final class CountdownController {
    private var timer: Timer?
    private let onTick: (Date) -> Void

    init(onTick: @escaping (Date) -> Void) { self.onTick = onTick }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh(at: Date()) }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh(at: Date())
    }

    func refresh(at now: Date) { onTick(now) }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
