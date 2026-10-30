import AppKit
import Combine
import NotchCore

enum DeckTab: String, CaseIterable, Identifiable {
    case music, clipboard, files, timer
    var id: String { rawValue }
    var title: String {
        switch self { case .music: "Музыка"; case .clipboard: "Буфер"; case .files: "Файлы"; case .timer: "Таймер" }
    }
    var symbol: String {
        switch self { case .music: "waveform"; case .clipboard: "doc.on.clipboard";
        case .files: "tray"; case .timer: "timer" }
    }
}

struct DisplayChoice: Identifiable {
    let id: UInt32
    let name: String
    let hasCamera: Bool
}

@MainActor
final class DeckModel: ObservableObject {
    let media: MediaController
    let clipboard: ClipboardController
    let focusTimer: FocusTimer
    let shelf: FileShelf
    let settings: SettingsStore
    let isPreview: Bool
    @Published var selectedTab: DeckTab = .music
    @Published var expanded = false
    @Published var pinned = false
    @Published var geometry: DisplayGeometry?
    @Published var displays: [DisplayChoice] = []
    @Published var notice: String?
    @Published var clipboardFocusRequest = UUID()
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onToggle: () -> Void = {}
    var onFocusClipboard: () -> Void = {}

    init(preview: Bool = false) {
        isPreview = preview
        settings = SettingsStore(preview: preview)
        media = MediaController(preview: preview)
        clipboard = ClipboardController(preview: preview)
        focusTimer = FocusTimer(preview: preview)
        shelf = FileShelf(preview: preview)
        focusTimer.soundEnabled = { [weak settings] in settings?.timerSound ?? false }
    }
}
