import AppKit
import Combine
import CoreGraphics
import Foundation

enum MediaSource: String, CaseIterable, Identifiable, Sendable {
    case system
    case music
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "система"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    fileprivate var bundleIdentifier: String? {
        switch self {
        case .system: return nil
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

@MainActor
final class MediaController: ObservableObject {
    @Published var source: MediaSource {
        didSet {
            guard source != oldValue else { return }
            if !preview {
                UserDefaults.standard.set(source.rawValue, forKey: "mediaSource")
            }
            generation &+= 1
            blockedSource = nil
            clearSnapshot()
            if preview {
                showPreview()
            } else if started {
                refresh()
            }
        }
    }

    @Published private(set) var title = "Системный проигрыватель"
    @Published private(set) var artist = "Управление текущим плеером macOS"
    @Published private(set) var isPlaying: Bool?
    @Published private(set) var duration: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    @Published private(set) var systemAccessGranted: Bool

    var sourceName: String {
        source == .system ? "текущий плеер macOS" : source.title
    }

    var appIcon: NSImage? {
        guard let identifier = source.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private let preview: Bool
    private let scriptQueue = DispatchQueue(label: "ru.dayanegosha.notchdeck.media", qos: .utility)
    private var timer: Timer?
    private var started = false
    private var inFlight = false
    private var generation: UInt = 0
    private var blockedSource: MediaSource?

    init(preview: Bool = false) {
        self.preview = preview
        source = preview ? .system : MediaSource(
            rawValue: UserDefaults.standard.string(forKey: "mediaSource") ?? ""
        ) ?? .system
        systemAccessGranted = preview || CGPreflightPostEventAccess()
        if preview {
            showPreview()
        } else {
            clearSnapshot()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard !started else { return }
        started = true
        guard !preview else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        generation &+= 1
        isBusy = false
    }

    func refresh() {
        guard !preview else { return }
        if source == .system {
            systemAccessGranted = CGPreflightPostEventAccess()
            if systemAccessGranted {
                status = nil
            }
            return
        }
        blockedSource = nil
        perform(.refresh)
    }

    func togglePlayback() {
        if preview {
            isPlaying = !(isPlaying ?? false)
            return
        }
        perform(.toggle)
    }

    func previous() {
        guard !preview else { return }
        perform(.previous)
    }

    func next() {
        guard !preview else { return }
        perform(.next)
    }

    func requestSystemAccess() {
        guard !preview else { return }
        systemAccessGranted = CGRequestPostEventAccess()
        status = systemAccessGranted ? nil : Self.systemAccessMessage
    }

    private func poll() {
        guard started, !preview else { return }
        if source == .system {
            systemAccessGranted = CGPreflightPostEventAccess()
            if systemAccessGranted {
                status = nil
            }
        } else if blockedSource != source {
            perform(.refresh)
        }
    }

    private func perform(_ action: Action) {
        if source == .system {
            guard action != .refresh else { return }
            sendSystemKey(action)
            return
        }
        guard !inFlight else { return }
        guard let identifier = source.bundleIdentifier,
              NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains(where: { !$0.isTerminated }) else {
            clearSnapshot()
            status = "\(source.title) не запущен"
            return
        }

        let requestedSource = source
        let requestedGeneration = generation
        inFlight = true
        isBusy = true
        status = nil
        scriptQueue.async { [weak self] in
            let result = Self.execute(source: requestedSource, action: action)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.isBusy = false
                guard self.generation == requestedGeneration, self.source == requestedSource else {
                    if self.started {
                        self.refresh()
                    }
                    return
                }
                switch result {
                case .success(let snapshot):
                    self.title = snapshot.title.isEmpty ? requestedSource.title : snapshot.title
                    self.artist = snapshot.artist
                    self.isPlaying = snapshot.playing
                    self.duration = snapshot.duration
                    self.elapsed = snapshot.elapsed
                    self.status = snapshot.title.isEmpty ? "В плеере ничего не выбрано" : nil
                case .failure(let failure):
                    self.clearSnapshot()
                    self.status = failure.message
                    if failure.authorizationDenied {
                        self.blockedSource = requestedSource
                    }
                }
            }
        }
    }

    private func sendSystemKey(_ action: Action) {
        systemAccessGranted = CGPreflightPostEventAccess()
        guard systemAccessGranted else {
            status = Self.systemAccessMessage
            return
        }
        guard let key = action.mediaKey else { return }
        // NX_SUBTYPE_AUX_CONTROL_BUTTONS и парные NX_KEYDOWN / NX_KEYUP из IOKit.
        let events = [10, 11].compactMap { state in
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (key << 16) | (state << 8),
                data2: -1
            )?.cgEvent
        }
        guard events.count == 2 else {
            status = "Не удалось создать медиаклавишу"
            return
        }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
        // Системные клавиши не подтверждают ни адресата, ни новое состояние плеера.
        status = "Медиаклавиша отправлена текущему плееру macOS"
    }

    private func clearSnapshot() {
        title = source == .system ? "Системный проигрыватель" : source.title
        artist = source == .system ? "Управление текущим плеером macOS" : ""
        isPlaying = nil
        duration = 0
        elapsed = 0
        status = nil
    }

    private func showPreview() {
        title = "Демонстрационный трек"
        artist = "Режим предпросмотра"
        isPlaying = true
        duration = 218
        elapsed = 74
        status = nil
    }

    private static let systemAccessMessage =
        "Разреши управление в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ"

    private enum Action: Sendable {
        case refresh
        case toggle
        case previous
        case next

        var scriptCommand: String {
            switch self {
            case .refresh: return ""
            case .toggle: return "playpause"
            case .previous: return "previous track"
            case .next: return "next track"
            }
        }

        var mediaKey: Int? {
            switch self {
            case .refresh: return nil
            case .toggle: return 16
            case .previous: return 18
            case .next: return 17
            }
        }
    }

    private struct Snapshot: Sendable {
        let title: String
        let artist: String
        let playing: Bool
        let duration: Double
        let elapsed: Double
    }

    private struct Failure: Error, Sendable {
        let message: String
        var authorizationDenied = false
    }

    nonisolated private static func execute(source: MediaSource, action: Action) -> Result<Snapshot, Failure> {
        autoreleasepool {
            guard let script = NSAppleScript(source: scriptSource(source: source, action: action)) else {
                return .failure(Failure(message: "Не удалось подготовить управление плеером"))
            }
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if let error {
                let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                switch number {
                case -1743, -1744:
                    return .failure(Failure(
                        message: "Разреши управление \(source.title) в Системных настройках → Конфиденциальность и безопасность → Автоматизация",
                        authorizationDenied: true
                    ))
                case -1712:
                    return .failure(Failure(message: "\(source.title) не ответил вовремя"))
                case -600, -609:
                    return .failure(Failure(message: "\(source.title) не запущен"))
                default:
                    return .failure(Failure(message: "Не удалось получить ответ от \(source.title)"))
                }
            }
            guard descriptor.numberOfItems == 6,
                  descriptor.atIndex(1)?.stringValue == "ok",
                  let playing = descriptor.atIndex(2),
                  let title = descriptor.atIndex(3)?.stringValue,
                  let artist = descriptor.atIndex(4)?.stringValue,
                  let duration = descriptor.atIndex(5)?.doubleValue,
                  let elapsed = descriptor.atIndex(6)?.doubleValue else {
                if descriptor.atIndex(1)?.stringValue == "notRunning" {
                    return .failure(Failure(message: "\(source.title) не запущен"))
                }
                return .failure(Failure(message: "Плеер вернул неполные данные"))
            }
            let divisor = source == .spotify ? 1000.0 : 1.0
            let seconds = duration.isFinite ? max(0, duration / divisor) : 0
            let position = elapsed.isFinite ? max(0, elapsed) : 0
            return .success(Snapshot(title: title, artist: artist, playing: playing.booleanValue,
                                     duration: seconds, elapsed: seconds > 0 ? min(position, seconds) : position))
        }
    }

    nonisolated private static func scriptSource(source: MediaSource, action: Action) -> String {
        // Оба значения выбираются из закрытых enum: данные пользователя не становятся кодом.
        let identifier = source == .spotify ? "com.spotify.client" : "com.apple.Music"
        return """
        with timeout of 3 seconds
            if application id "\(identifier)" is not running then return {"notRunning"}
            tell application id "\(identifier)"
                \(action.scriptCommand)
                set playingNow to (player state is playing)
                set trackTitle to ""
                set trackArtist to ""
                set trackDuration to 0
                set trackPosition to 0
                try
                    set currentItem to current track
                    set trackTitle to name of currentItem as text
                    set trackArtist to artist of currentItem as text
                    set trackDuration to duration of currentItem
                end try
                try
                    set trackPosition to player position
                end try
                return {"ok", playingNow, trackTitle, trackArtist, trackDuration, trackPosition}
            end tell
        end timeout
        """
    }
}
