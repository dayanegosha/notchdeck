import XCTest
@testable import NotchCore

final class FocusClockTests: XCTestCase {
    func testElapsedTimeIncludesSleepAndFinishesOnce() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1000)
        clock.start(seconds: 60, at: start)
        clock.tick(at: start.addingTimeInterval(90))
        XCTAssertEqual(clock.phase, .finished)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(90)), 0)
        clock.tick(at: start.addingTimeInterval(120))
        XCTAssertEqual(clock.phase, .finished)
    }

    func testPauseAndResumeDoNotConsumePausedTime() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1000)
        clock.start(seconds: 90, at: start)
        clock.pause(at: start.addingTimeInterval(30))
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(1000)), 60)
        clock.resume(at: start.addingTimeInterval(1000))
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(1020)), 40)
        clock.reset()
        XCTAssertEqual(clock.phase, .idle)
        XCTAssertEqual(clock.remaining(at: start), 90)
    }
}
