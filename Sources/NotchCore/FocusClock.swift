import Foundation

public struct FocusClock: Equatable {
    public enum Phase: String { case idle, running, paused, finished }
    public private(set) var phase: Phase = .idle
    public private(set) var duration: TimeInterval = 25 * 60
    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 25 * 60

    public init() {}

    public func remaining(at date: Date) -> TimeInterval {
        if phase == .running, let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return phase == .finished ? 0 : pausedRemaining
    }

    public mutating func start(seconds: TimeInterval, at date: Date) {
        duration = max(1, min(seconds, 24 * 60 * 60))
        pausedRemaining = duration
        endDate = date.addingTimeInterval(duration)
        phase = .running
    }

    public mutating func tick(at date: Date) {
        if phase == .running, remaining(at: date) <= 0 {
            endDate = nil
            pausedRemaining = 0
            phase = .finished
        }
    }

    public mutating func pause(at date: Date) {
        tick(at: date)
        guard phase == .running else { return }
        pausedRemaining = remaining(at: date)
        endDate = nil
        phase = .paused
    }

    public mutating func resume(at date: Date) {
        guard phase == .paused else { return }
        endDate = date.addingTimeInterval(pausedRemaining)
        phase = .running
    }

    public mutating func reset() {
        endDate = nil
        pausedRemaining = duration
        phase = .idle
    }
}
