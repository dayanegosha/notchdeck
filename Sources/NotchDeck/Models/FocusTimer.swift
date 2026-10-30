import AppKit
import Combine
import NotchCore

@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var phase: FocusClock.Phase = .idle
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published var selectedMinutes = 25
    var soundEnabled: () -> Bool = { true }
    private var clock = FocusClock()
    private var ticker: Timer?
    private let preview: Bool

    init(preview: Bool = false) { self.preview = preview }

    var formattedRemaining: String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var progress: Double { duration > 0 ? min(1, max(0, 1 - remaining / duration)) : 0 }

    func start(minutes: Int? = nil) {
        clock.start(seconds: Double(min(240, max(1, minutes ?? selectedMinutes))) * 60, at: Date())
        tick()
        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.1
        RunLoop.main.add(ticker!, forMode: .common)
    }

    func pauseOrResume() {
        if phase == .running {
            clock.pause(at: Date())
            ticker?.invalidate()
            ticker = nil
        } else if phase == .paused {
            clock.resume(at: Date())
            startTicker()
        }
        tick()
    }

    func reset() {
        clock.reset()
        ticker?.invalidate()
        ticker = nil
        tick()
    }

    func tick() {
        let previous = phase
        clock.tick(at: Date())
        phase = clock.phase
        remaining = clock.remaining(at: Date())
        duration = clock.duration
        if phase == .finished, previous != .finished {
            ticker?.invalidate()
            ticker = nil
            if !preview, soundEnabled() { NSSound(named: "Glass")?.play() }
        }
    }
}
