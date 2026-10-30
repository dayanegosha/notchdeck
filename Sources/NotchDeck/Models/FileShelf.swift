import AppKit
import Combine

struct ShelfItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

@MainActor
final class FileShelf: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var status: String?
    let maximum = 24
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        if preview { items = [ShelfItem(url: URL(fileURLWithPath: "/demo/Материалы проекта.pdf")),
                              ShelfItem(url: URL(fileURLWithPath: "/demo/Снимки экрана"))] }
    }

    func add(_ urls: [URL]) {
        guard !preview else { return }
        let existing = Set(items.map { $0.url.standardizedFileURL })
        let valid = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
        var seen = existing
        for url in valid {
            let url = url.standardizedFileURL
            if seen.insert(url).inserted, items.count < maximum { items.append(ShelfItem(url: url)) }
        }
        status = valid.count != urls.count ? "Некоторые файлы уже недоступны" : nil
        if items.count == maximum { status = "На полке помещается до \(maximum) файлов" }
    }

    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll(); status = nil }
    func reveal(_ item: ShelfItem) {
        guard !preview, item.exists else { status = "Файл перемещён или удалён"; return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
