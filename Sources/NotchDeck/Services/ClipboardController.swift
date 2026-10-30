import AppKit
import Combine
import CryptoKit
import ImageIO
import LocalAuthentication
import NotchCore
import Security

@MainActor
final class ClipboardController: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard !isPreview, oldValue != enabled else { return }
            defaults?.set(enabled, forKey: "clipboard.enabled")
            if enabled {
                start()
            } else {
                stopPolling()
                clear(includePinned: true)
                status = "история выключена и очищена"
            }
        }
    }
    @Published var persistsHistory: Bool {
        didSet {
            guard !isPreview, oldValue != persistsHistory else { return }
            defaults?.set(persistsHistory, forKey: "clipboard.persistsHistory")
            loadToken = nil
            persistenceVersion += 1
            persistenceReady = true
            if persistsHistory && enabled {
                saveHistory(immediate: true)
            } else {
                storage.erase(completion: storageCompletion(version: persistenceVersion))
            }
        }
    }
    @Published var maxItems: Int {
        didSet {
            guard oldValue != maxItems else { return }
            let limit = min(5000, max(1, maxItems))
            if maxItems != limit { maxItems = limit }
            history.setLimits(maxItems: limit)
            items = history.items
            if !isPreview {
                defaults?.set(limit, forKey: "clipboard.maxItems")
                loadToken = nil
                saveHistory(immediate: true)
            }
        }
    }
    @Published var excludedBundleIDs: String {
        didSet {
            guard !isPreview, oldValue != excludedBundleIDs else { return }
            defaults?.set(excludedBundleIDs, forKey: "clipboard.excludedBundleIDs")
            loadToken = nil
            history = ClipboardHistory(items: history.items.filter {
                ClipboardCapturePolicy.shouldCapture(types: [], sourceBundleID: $0.sourceBundleID,
                                                     exclusions: excludedBundleIDs)
            }, maxItems: maxItems)
            items = history.items
            saveHistory(immediate: true)
        }
    }
    @Published private(set) var items: [ClipboardItem]
    @Published private(set) var status: String?

    private let isPreview: Bool
    private let defaults: UserDefaults?
    private let storage = EncryptedClipboardStore()
    private var history: ClipboardHistory
    private var timer: Timer?
    private var lastChangeCount: Int?
    private var loadToken: UUID?
    private var hasLoadedHistory = false
    private var persistenceVersion = 0
    private var persistenceReady = true

    init(preview: Bool = false) {
        isPreview = preview
        defaults = preview ? nil : .standard
        enabled = preview ? false : defaults?.bool(forKey: "clipboard.enabled") ?? false
        persistsHistory = preview ? false : defaults?.bool(forKey: "clipboard.persistsHistory") ?? false
        let savedLimit = preview ? 500 : defaults?.integer(forKey: "clipboard.maxItems") ?? 0
        let limit = savedLimit > 0 ? min(5000, savedLimit) : 500
        maxItems = limit
        excludedBundleIDs = preview ? ClipboardCapturePolicy.defaultExcludedBundleIDs
            : defaults?.string(forKey: "clipboard.excludedBundleIDs") ?? ClipboardCapturePolicy.defaultExcludedBundleIDs
        let examples = preview ? Self.previewItems() : []
        let initialHistory = ClipboardHistory(items: examples, maxItems: limit)
        history = initialHistory
        items = initialHistory.items
        status = preview ? "демонстрационная история" : nil
    }

    func start() {
        guard !isPreview, enabled, timer == nil else { return }
        // Старый буфер не читается: согласие действует только на последующие копирования.
        lastChangeCount = NSPasteboard.general.changeCount
        if persistsHistory && !hasLoadedHistory { restoreHistory() }
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        stopPolling()
        if !isPreview { storage.flush() }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        lastChangeCount = nil
        loadToken = nil
    }

    func copy(_ item: ClipboardItem) {
        guard !isPreview else { status = "демо: путь и буфер обмена не изменяются"; return }
        guard ClipboardCapturePolicy.accepts(item) else { status = "запись повреждена или слишком велика"; return }
        var objects: [NSPasteboardWriting] = []
        switch item.kind {
        case .text:
            let value = NSPasteboardItem()
            guard value.setString(item.text!, forType: .string) else { return }
            objects = [value]
        case .image:
            let data = item.imageData!
            guard let type = Self.imageType(data) else { status = "формат изображения не поддерживается"; return }
            let value = NSPasteboardItem()
            guard value.setData(data, forType: type) else { return }
            objects = [value]
        case .files:
            if let missing = item.filePaths.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
                status = "файл недоступен: \(URL(fileURLWithPath: missing).lastPathComponent)"
                return
            }
            objects = item.filePaths.map { NSURL(fileURLWithPath: $0) }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.writeObjects(objects)
        lastChangeCount = pasteboard.changeCount
        status = success ? "скопировано — вставь через ⌘V" : "не удалось записать в буфер обмена"
    }

    func togglePin(_ item: ClipboardItem) {
        loadToken = nil
        history.togglePin(id: item.id)
        items = history.items
        saveHistory()
    }

    func remove(_ item: ClipboardItem) {
        loadToken = nil
        history.remove(id: item.id)
        items = history.items
        saveHistory(immediate: true)
    }

    func clear(includePinned: Bool = false) {
        loadToken = nil
        hasLoadedHistory = true
        persistenceReady = true
        history.clear(includePinned: includePinned)
        items = history.items
        persistenceVersion += 1
        guard !isPreview else { return }
        if enabled && persistsHistory && !items.isEmpty {
            storage.save(items, immediate: true, removePrevious: true,
                         completion: storageCompletion(version: persistenceVersion))
        } else {
            storage.erase(completion: storageCompletion(version: persistenceVersion))
        }
    }

    private func poll() {
        guard enabled, timer != nil, !isPreview else { return }
        let pasteboard = NSPasteboard.general
        let change = pasteboard.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let source = NSWorkspace.shared.frontmostApplication
        // Сначала проверяются только типы и приложение, без чтения содержимого.
        guard ClipboardCapturePolicy.shouldCapture(types: types, sourceBundleID: source?.bundleIdentifier,
                                                   exclusions: excludedBundleIDs) else { return }
        let declaredSource = pasteboard.string(forType: .init("org.nspasteboard.source"))
        let sourceID = (declaredSource ?? source?.bundleIdentifier).map { String($0.prefix(512)) }
        guard ClipboardCapturePolicy.shouldCapture(types: types, sourceBundleID: sourceID,
                                                   exclusions: excludedBundleIDs) else { return }
        let name = String((source?.localizedName ?? "приложение").prefix(256))
        var captured: ClipboardItem?
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            captured = ClipboardItem(kind: .files, filePaths: urls.map(\.path),
                                     sourceName: name, sourceBundleID: sourceID)
        } else if let type = pasteboard.availableType(from: [.png, .tiff]), let data = pasteboard.data(forType: type) {
            guard data.count <= ClipboardCapturePolicy.maxImageBytes, Self.isReasonableImage(data) else {
                status = "изображение пропущено: до 8 МиБ, 40 млн пикселей и 16 384 по стороне"
                return
            }
            captured = ClipboardItem(kind: .image, imageData: data, sourceName: name, sourceBundleID: sourceID)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            captured = ClipboardItem(kind: .text, text: text, sourceName: name, sourceBundleID: sourceID)
        }
        guard pasteboard.changeCount == change, let captured else { return }
        guard ClipboardCapturePolicy.accepts(captured) else {
            status = "запись пропущена: текст и пути до 1 МиБ, не более 4096 файлов"
            return
        }
        let retained = history.insert(captured)
        items = history.items
        status = retained ? nil : "лимит истории занят закреплёнными записями"
        saveHistory()
    }

    private func restoreHistory() {
        let token = UUID()
        loadToken = token
        storage.load { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.persistsHistory, self.loadToken == token else { return }
                self.loadToken = nil
                self.hasLoadedHistory = true
                switch result {
                case .success(let saved):
                    let allowed = saved.filter {
                        ClipboardCapturePolicy.shouldCapture(types: [], sourceBundleID: $0.sourceBundleID,
                                                             exclusions: self.excludedBundleIDs)
                            && ($0.kind != .image || $0.imageData.map(Self.isReasonableImage) == true)
                    }
                    self.history = ClipboardHistory(items: self.items + allowed, maxItems: self.maxItems)
                    self.items = self.history.items
                    self.saveHistory(immediate: true)
                case .failure:
                    self.persistenceReady = false
                    self.status = "не удалось открыть зашифрованную историю; новые записи остаются в памяти"
                }
            }
        }
    }

    private func saveHistory(immediate: Bool = false) {
        guard !isPreview, enabled, persistsHistory, persistenceReady, loadToken == nil else { return }
        persistenceVersion += 1
        storage.save(items, immediate: immediate,
                     completion: storageCompletion(version: persistenceVersion))
    }

    private func storageCompletion(version: Int) -> @Sendable (Bool) -> Void {
        { [weak self] success in
            guard !success else { return }
            Task { @MainActor [weak self] in
                guard let self, self.persistenceVersion == version else { return }
                self.status = "не удалось обновить зашифрованную историю на диске"
            }
        }
    }

    private static func imageType(_ data: Data) -> NSPasteboard.PasteboardType? {
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return .png }
        if data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42]) { return .tiff }
        return nil
    }

    private static func isReasonableImage(_ data: Data) -> Bool {
        guard imageType(data) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        let pixels = width.doubleValue * height.doubleValue
        return width.doubleValue > 0 && height.doubleValue > 0
            && width.doubleValue <= 16_384 && height.doubleValue <= 16_384 && pixels <= 40_000_000
    }

    private static func previewItems() -> [ClipboardItem] {
        [ClipboardItem(kind: .text, text: "swift build -c release", sourceName: "Терминал", isPinned: true),
         ClipboardItem(kind: .text, text: "идеи для выходных\nвелосипед, музей и хороший кофе", sourceName: "Заметки"),
         ClipboardItem(kind: .files, filePaths: ["/demo/документы/план-проекта.pdf"], sourceName: "Finder")]
    }
}

private struct ClipboardArchive: Codable {
    let version: Int
    let items: [ClipboardItem]
}

private enum ClipboardStorageError: Error { case unavailable, invalidArchive }

private final class EncryptedClipboardStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NotchDeck.clipboard.storage", qos: .utility)
    private var generation = 0
    private var pending: DispatchWorkItem?
    private let service = "NotchDeck.clipboard.encryption"
    private let account = "history-aes-256-v1"
    private let context = Data("NotchDeck.clipboard.v1".utf8)

    func load(completion: @escaping @Sendable (Result<[ClipboardItem], Error>) -> Void) {
        queue.async {
            do {
                let file = try self.archiveURL()
                guard FileManager.default.fileExists(atPath: file.path) else { completion(.success([])); return }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= ClipboardHistory.defaultMaxBytes * 3 else {
                    throw ClipboardStorageError.invalidArchive
                }
                let encrypted = try Data(contentsOf: file, options: .mappedIfSafe)
                let key = try self.key(create: false)
                let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key,
                                                 authenticating: self.context)
                let archive = try PropertyListDecoder().decode(ClipboardArchive.self, from: plaintext)
                guard archive.version == 1 else { throw ClipboardStorageError.invalidArchive }
                completion(.success(archive.items))
            } catch { completion(.failure(error)) }
        }
    }

    func save(_ items: [ClipboardItem], immediate: Bool = false, removePrevious: Bool = false,
              completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            self.generation += 1
            let token = self.generation
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak store = self] in
                guard let store, store.generation == token else { return }
                store.pending = nil
                do {
                    let file = try store.archiveURL()
                    if removePrevious && FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                    }
                    let key = try store.key(create: true)
                    let encoder = PropertyListEncoder()
                    encoder.outputFormat = .binary
                    let plaintext = try encoder.encode(ClipboardArchive(version: 1, items: items))
                    guard let encrypted = try AES.GCM.seal(plaintext, using: key,
                                                          authenticating: store.context).combined else {
                        throw ClipboardStorageError.unavailable
                    }
                    let parent = file.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                    try encrypted.write(to: file, options: [.atomic])
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    completion(true)
                } catch { completion(false) }
            }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + (immediate ? 0 : 0.35), execute: work)
        }
    }

    func erase(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            self.generation += 1
            self.pending?.cancel()
            self.pending = nil
            do {
                let file = try self.archiveURL()
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                let result = SecItemDelete(self.keyQuery() as CFDictionary)
                guard result == errSecSuccess || result == errSecItemNotFound else {
                    throw ClipboardStorageError.unavailable
                }
                completion(true)
            } catch { completion(false) }
        }
    }

    func flush() {
        // При завершении приложения не оставляем последнюю запись в отложенном блоке.
        queue.sync {
            let work = pending
            pending = nil
            work?.perform()
            generation += 1
            work?.cancel()
        }
    }

    private func archiveURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false)
        return support.appendingPathComponent("NotchDeck", isDirectory: true).appendingPathComponent("clipboard.enc")
    }

    private func keyQuery() -> [String: Any] {
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: authentication]
    }

    private func key(create: Bool) throws -> SymmetricKey {
        var query = keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecSuccess, let data = value as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard result == errSecItemNotFound, create else { throw ClipboardStorageError.unavailable }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var entry = keyQuery()
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        entry[kSecValueData as String] = data
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else {
            throw ClipboardStorageError.unavailable
        }
        return key
    }
}
