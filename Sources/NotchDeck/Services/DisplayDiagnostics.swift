import AppKit
import NotchCore

enum DisplayDiagnostics {
    static func json() -> Data? {
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let snapshot = DisplaySnapshot(id: id, frame: screen.frame, safeTop: screen.safeAreaInsets.top,
                                           auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea,
                                           menuBarHeight: max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY))
            let geometry = DisplayGeometry.resolve(snapshot)
            return ["id": id, "name": screen.localizedName,
                    "frame": rect(screen.frame), "scale": screen.backingScaleFactor,
                    "safeTop": screen.safeAreaInsets.top,
                    "camera": geometry.cameraFrame.map(rect) ?? NSNull(),
                    "compact": rect(geometry.compactFrame), "expanded": rect(geometry.expandedFrame)]
        }
        return try? JSONSerialization.data(withJSONObject: ["version": "0.1.0", "screens": screens], options: [.prettyPrinted, .sortedKeys])
    }

    private static func rect(_ value: CGRect) -> [String: CGFloat] {
        ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }
}
