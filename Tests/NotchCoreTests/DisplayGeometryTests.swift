import XCTest
@testable import NotchCore

final class DisplayGeometryTests: XCTestCase {
    func testUsesActualAsymmetricCameraGapInGlobalCoordinates() {
        let screen = DisplaySnapshot(id: 4, frame: CGRect(x: -1920, y: 120, width: 1512, height: 982),
            safeTop: 32, auxiliaryLeft: CGRect(x: -1920, y: 1070, width: 640, height: 32),
            auxiliaryRight: CGRect(x: -1080, y: 1070, width: 672, height: 32))
        let result = DisplayGeometry.resolve(screen)
        XCTAssertEqual(result.cameraFrame, CGRect(x: -1280, y: 1070, width: 200, height: 32))
        XCTAssertEqual(result.compactFrame.midX, -1180)
        XCTAssertEqual(result.compactFrame.maxY, 1102)
        XCTAssertEqual(result.expandedFrame.maxY, result.compactFrame.minY)
    }

    func testPositiveInsetWithoutAuxiliaryAreasDoesNotInventCamera() {
        let geometry = DisplayGeometry.resolve(DisplaySnapshot(id: 1,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: 32))
        XCTAssertFalse(geometry.hasCamera)
        XCTAssertLessThan(geometry.compactFrame.maxY, 900 - 32)
    }

    func testSelectionSurvivesDisconnectedDisplayAndPrefersCamera() {
        let external = DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeTop: 0)
        let laptop = DisplaySnapshot(id: 2, frame: CGRect(x: 1920, y: -200, width: 1512, height: 982), safeTop: 32,
            auxiliaryLeft: CGRect(x: 1920, y: 750, width: 660, height: 32),
            auxiliaryRight: CGRect(x: 2780, y: 750, width: 652, height: 32))
        XCTAssertEqual(DisplayGeometry.select(from: [external, laptop], preferredID: 99)?.id, 2)
        XCTAssertEqual(DisplayGeometry.select(from: [external, laptop], preferredID: 1)?.id, 1)
        XCTAssertNil(DisplayGeometry.select(from: [], preferredID: nil))
    }

    func testExternalDisplayUsesCapsuleBelowMenuAndKeepsBodyOnScreen() {
        let screen = DisplaySnapshot(id: 7, frame: CGRect(x: -2560, y: -400, width: 2560, height: 1440), safeTop: 0)
        let geometry = DisplayGeometry.resolve(screen)
        XCTAssertFalse(geometry.hasCamera)
        XCTAssertEqual(geometry.compactFrame.midX, -1280)
        XCTAssertEqual(geometry.compactFrame.maxY, screen.frame.maxY - 30)
        XCTAssertTrue(screen.frame.contains(geometry.expandedFrame))
        XCTAssertEqual(geometry.expandedFrame.maxY, geometry.compactFrame.minY)
    }

    func testOverlappingAuxiliaryAreasAreNotACamera() {
        let geometry = DisplayGeometry.resolve(DisplaySnapshot(id: 1,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 868, width: 800, height: 32),
            auxiliaryRight: CGRect(x: 700, y: 868, width: 740, height: 32)))
        XCTAssertFalse(geometry.hasCamera)
    }

    func testExpandedWidthFitsSmallerScaledDisplay() {
        let screen = DisplaySnapshot(id: 1, frame: CGRect(x: 2400, y: 800, width: 600, height: 700), safeTop: 0)
        let geometry = DisplayGeometry.resolve(screen)
        XCTAssertEqual(geometry.expandedFrame.width, 568)
        XCTAssertTrue(screen.frame.contains(geometry.expandedFrame))
    }

    func testExternalCapsuleRespectsLargerSystemMenuBar() {
        let geometry = DisplayGeometry.resolve(DisplaySnapshot(id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeTop: 0,
            menuBarHeight: 40))
        XCTAssertEqual(geometry.compactFrame.maxY, 1034)
    }
}
