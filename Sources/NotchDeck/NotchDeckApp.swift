import AppKit
import SwiftUI

@main
struct NotchDeckApp: App {
    var body: some Scene {
        WindowGroup {
            Text(".notchdeck")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .frame(width: 620, height: 402)
                .preferredColorScheme(.dark)
        }
    }
}
