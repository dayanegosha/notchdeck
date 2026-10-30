import AppKit
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var opensOnHover: Bool { didSet { defaults.set(opensOnHover, forKey: "opensOnHover") } }
    @Published var showsInFullScreen: Bool { didSet { defaults.set(showsInFullScreen, forKey: "showsInFullScreen") } }
    @Published var shortcutsEnabled: Bool { didSet { defaults.set(shortcutsEnabled, forKey: "shortcutsEnabled") } }
    @Published var timerSound: Bool { didSet { defaults.set(timerSound, forKey: "timerSound") } }
    @Published var selectedDisplayID: UInt32? {
        didSet { defaults.set(selectedDisplayID.map { Int($0) }, forKey: "selectedDisplayID") }
    }

    init(preview: Bool = false) {
        defaults = preview ? UserDefaults(suiteName: "NotchDeck.Preview")! : .standard
        opensOnHover = defaults.object(forKey: "opensOnHover") as? Bool ?? true
        showsInFullScreen = defaults.object(forKey: "showsInFullScreen") as? Bool ?? false
        shortcutsEnabled = defaults.object(forKey: "shortcutsEnabled") as? Bool ?? true
        timerSound = defaults.object(forKey: "timerSound") as? Bool ?? true
        selectedDisplayID = (defaults.object(forKey: "selectedDisplayID") as? Int).flatMap { UInt32(exactly: $0) }
    }
}
