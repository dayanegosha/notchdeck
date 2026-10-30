import Foundation
import CoreGraphics

public struct DisplaySnapshot: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let safeTop: CGFloat
    public let auxiliaryLeft: CGRect?
    public let auxiliaryRight: CGRect?

    public init(id: UInt32, frame: CGRect, safeTop: CGFloat,
                auxiliaryLeft: CGRect? = nil, auxiliaryRight: CGRect? = nil) {
        self.id = id
        self.frame = frame
        self.safeTop = safeTop
        self.auxiliaryLeft = auxiliaryLeft
        self.auxiliaryRight = auxiliaryRight
    }
}

public struct DisplayGeometry: Equatable {
    public let displayID: UInt32
    public let screenFrame: CGRect
    public let cameraFrame: CGRect?
    public let compactFrame: CGRect
    public let expandedFrame: CGRect
    public var hasCamera: Bool { cameraFrame != nil }
    public var cameraWidth: CGFloat { cameraFrame?.width ?? 0 }

    public static func resolve(_ screen: DisplaySnapshot) -> DisplayGeometry {
        let frame = screen.frame
        var camera: CGRect?
        if screen.safeTop > 0, screen.safeTop < frame.height / 3,
           let left = screen.auxiliaryLeft, let right = screen.auxiliaryRight,
           left.width > 0, right.width > 0, left.maxX < right.minX,
           left.maxX >= frame.minX, right.minX <= frame.maxX {
            camera = CGRect(x: left.maxX, y: frame.maxY - screen.safeTop,
                            width: right.minX - left.maxX, height: screen.safeTop)
        }
        let compactHeight = camera?.height ?? 28
        let compactWidth = max(1, min(frame.width - 24, (camera?.width ?? 112) + 64))
        let center = camera?.midX ?? frame.midX
        // Внешняя панель находится ниже меню; широкое окно не перекрывает его клики.
        let compactTop = camera == nil ? frame.maxY - max(screen.safeTop, 24) - 6 : frame.maxY
        let compact = CGRect(x: center - compactWidth / 2, y: compactTop - compactHeight,
                             width: compactWidth, height: compactHeight)
        let width = max(1, min(620, frame.width - 32))
        let height = max(1, min(402, frame.height - 96))
        let x = min(max(center - width / 2, frame.minX + 16), frame.maxX - width - 16)
        let expanded = CGRect(x: x, y: compact.minY - height, width: width, height: height)
        return DisplayGeometry(displayID: screen.id, screenFrame: frame,
                               cameraFrame: camera, compactFrame: compact, expandedFrame: expanded)
    }

    public static func select(from screens: [DisplaySnapshot], preferredID: UInt32?) -> DisplaySnapshot? {
        if let preferredID, let preferred = screens.first(where: { $0.id == preferredID }) {
            return preferred
        }
        return screens.first(where: { resolve($0).hasCamera }) ?? screens.first
    }
}
