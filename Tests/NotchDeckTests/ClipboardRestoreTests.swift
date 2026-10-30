import AppKit
import Combine
import NotchCore
import XCTest
@testable import NotchDeck

final class ClipboardRestoreTests: XCTestCase {
    @MainActor
    func testChangingLimitDuringRestoreKeepsArchiveAndUsesTheNewLimit() async {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.controller.start()
        fixture.controller.maxItems = 2
        XCTAssertEqual(fixture.storage.loadCount, 1)
        XCTAssertTrue(fixture.storage.saves.isEmpty)
        let saved = [entry("первое"), entry("второе"), entry("третье")]

        await finishRestore(fixture, saved: saved)

        XCTAssertEqual(fixture.controller.items.map(\.text), ["первое", "второе"])
        XCTAssertEqual(fixture.storage.saves.last?.items, fixture.controller.items)
        XCTAssertEqual(fixture.storage.eraseCount, 0)
    }

    @MainActor
    func testChangingExclusionsDuringRestoreFiltersTheLoadedArchiveWithoutDiscardingIt() async {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.controller.start()
        fixture.controller.excludedBundleIDs = "com.example.private"
        XCTAssertTrue(fixture.storage.saves.isEmpty)
        let allowed = entry("сохранить", source: "com.example.editor")
        let excluded = entry("исключить", source: "com.example.private")

        await finishRestore(fixture, saved: [allowed, excluded])

        XCTAssertEqual(fixture.controller.items, [allowed])
        XCTAssertEqual(fixture.storage.saves.last?.items, [allowed])
        XCTAssertEqual(fixture.storage.eraseCount, 0)
    }

    @MainActor
    func testPinAndRemoveWaitForRestoreInsteadOfOverwritingTheWholeArchive() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let saved = [entry("закреплено", pinned: true), entry("обычная запись")]
        fixture.controller.start()
        fixture.controller.togglePin(saved[0])
        fixture.controller.remove(saved[1])
        XCTAssertEqual(fixture.controller.status, "история ещё загружается")
        XCTAssertTrue(fixture.storage.saves.isEmpty)
        XCTAssertEqual(fixture.storage.eraseCount, 0)

        await finishRestore(fixture, saved: saved)

        XCTAssertEqual(fixture.controller.items, saved)
        XCTAssertNil(fixture.controller.status)
    }

    @MainActor
    func testClearUnpinnedWaitsForRestoreAndCanThenPreserveRestoredPins() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let pinned = entry("важное", pinned: true)
        fixture.controller.start()
        fixture.controller.clear()
        XCTAssertEqual(fixture.controller.status, "история ещё загружается")
        XCTAssertTrue(fixture.storage.saves.isEmpty)
        XCTAssertEqual(fixture.storage.eraseCount, 0)

        await finishRestore(fixture, saved: [pinned, entry("обычное")])
        XCTAssertEqual(fixture.controller.items.count, 2)
        fixture.controller.clear()

        XCTAssertEqual(fixture.controller.items, [pinned])
        XCTAssertEqual(fixture.storage.saves.last?.items, [pinned])
        XCTAssertEqual(fixture.storage.saves.last?.removePrevious, true)
    }

    @MainActor
    func testExplicitClearAllCancelsRestoreAndLateCompletionCannotResurrectIt() async {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.controller.start()
        fixture.controller.clear(includePinned: true)
        XCTAssertEqual(fixture.storage.eraseCount, 1)

        await completeCancelledRestore(fixture, saved: [entry("старая запись", pinned: true)])

        XCTAssertTrue(fixture.controller.items.isEmpty)
        XCTAssertTrue(fixture.storage.saves.isEmpty)
    }

    @MainActor
    func testDisablingCaptureCancelsRestoreAndErasesRatherThanResavingItsData() async {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.controller.start()
        fixture.controller.enabled = false
        XCTAssertFalse(fixture.defaults.bool(forKey: "clipboard.enabled"))
        XCTAssertEqual(fixture.storage.eraseCount, 1)

        await completeCancelledRestore(fixture, saved: [entry("старая запись")])

        XCTAssertTrue(fixture.controller.items.isEmpty)
        XCTAssertTrue(fixture.storage.saves.isEmpty)
    }

    @MainActor
    func testDisablingPersistenceCancelsRestoreWithoutAReplayAfterTheErase() async {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.controller.start()
        fixture.controller.persistsHistory = false
        XCTAssertFalse(fixture.defaults.bool(forKey: "clipboard.persistsHistory"))
        XCTAssertEqual(fixture.storage.eraseCount, 1)

        await completeCancelledRestore(fixture, saved: [entry("старая запись")])

        XCTAssertTrue(fixture.controller.items.isEmpty)
        XCTAssertTrue(fixture.storage.saves.isEmpty)
    }

    @MainActor
    func testPreviewNeverCallsStorageChangesPreferencesOrTouchesTheProvidedPasteboard() {
        let fixture = Fixture(preview: true)
        defer { fixture.close() }
        let change = fixture.pasteboard.changeCount
        XCTAssertFalse(fixture.controller.enabled)
        XCTAssertFalse(fixture.controller.persistsHistory)
        fixture.defaults.set(false, forKey: "clipboard.enabled")
        fixture.defaults.set(false, forKey: "clipboard.persistsHistory")
        fixture.controller.start()
        fixture.controller.enabled = true
        fixture.controller.persistsHistory = true
        fixture.controller.maxItems = 10
        fixture.controller.excludedBundleIDs = "com.example.private"
        fixture.controller.copy(fixture.controller.items[0])
        fixture.controller.clear(includePinned: true)
        fixture.controller.stop()

        XCTAssertEqual(fixture.storage.loadCount, 0)
        XCTAssertEqual(fixture.storage.eraseCount, 0)
        XCTAssertEqual(fixture.storage.flushCount, 0)
        XCTAssertTrue(fixture.storage.saves.isEmpty)
        XCTAssertFalse(fixture.defaults.bool(forKey: "clipboard.enabled"))
        XCTAssertFalse(fixture.defaults.bool(forKey: "clipboard.persistsHistory"))
        XCTAssertEqual(fixture.pasteboard.changeCount, change)
    }

    @MainActor
    private func entry(_ text: String, pinned: Bool = false, source: String = "com.example.editor") -> ClipboardItem {
        ClipboardItem(kind: .text, text: text, sourceName: "тестовое приложение",
                      sourceBundleID: source, isPinned: pinned)
    }

    @MainActor
    private func finishRestore(_ fixture: Fixture, saved: [ClipboardItem]) async {
        let restored = expectation(description: "restored archive is saved after the merge")
        fixture.storage.onSave = { restored.fulfill() }
        fixture.storage.completeLoad(with: saved)
        await fulfillment(of: [restored], timeout: 1)
        fixture.storage.onSave = nil
    }

    @MainActor
    private func completeCancelledRestore(_ fixture: Fixture, saved: [ClipboardItem]) async {
        let rewritten = expectation(description: "cancelled restore must not write a snapshot")
        rewritten.isInverted = true
        fixture.storage.onSave = { rewritten.fulfill() }
        fixture.storage.completeLoad(with: saved)
        await fulfillment(of: [rewritten], timeout: 0.05)
        fixture.storage.onSave = nil
    }
}

@MainActor
private final class Fixture {
    let suiteName = "NotchDeck.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let pasteboard = NSPasteboard.withUniqueName()
    let storage = DelayedClipboardStorage()
    let controller: ClipboardController

    init(preview: Bool = false, enabled: Bool = true) {
        let suiteName = suiteName
        let preferences = UserDefaults(suiteName: suiteName)!
        preferences.removePersistentDomain(forName: suiteName)
        preferences.set(enabled, forKey: "clipboard.enabled")
        preferences.set(true, forKey: "clipboard.persistsHistory")
        preferences.set("", forKey: "clipboard.excludedBundleIDs")
        defaults = preferences
        pasteboard.setString("синтетический исходный буфер", forType: .string)
        controller = ClipboardController(preview: preview, storage: storage,
                                         defaults: preferences, pasteboard: pasteboard)
    }

    func close() {
        controller.stop()
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class DelayedClipboardStorage: ClipboardStorage {
    struct SavedSnapshot {
        let items: [ClipboardItem]
        let removePrevious: Bool
    }
    private var loadCompletion: (@Sendable (Result<[ClipboardItem], Error>) -> Void)?
    private(set) var loadCount = 0
    private(set) var eraseCount = 0
    private(set) var flushCount = 0
    private(set) var saves: [SavedSnapshot] = []
    var onSave: (() -> Void)?

    func load(completion: @escaping @Sendable (Result<[ClipboardItem], Error>) -> Void) {
        loadCount += 1
        loadCompletion = completion
    }

    func completeLoad(with items: [ClipboardItem]) {
        let completion = loadCompletion
        loadCompletion = nil
        completion?(.success(items))
    }

    func save(_ items: [ClipboardItem], immediate: Bool, removePrevious: Bool,
              completion: @escaping @Sendable (Bool) -> Void) {
        saves.append(SavedSnapshot(items: items, removePrevious: removePrevious))
        completion(true)
        onSave?()
    }

    func erase(completion: @escaping @Sendable (Bool) -> Void) {
        eraseCount += 1
        completion(true)
    }

    func flush() { flushCount += 1 }
}
