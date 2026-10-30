import AppKit
import NotchCore
import SwiftUI

@MainActor
struct DeckView: View {
    @ObservedObject var model: DeckModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTargeted = false
    @State private var clipboardSearchRequested = false

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 5) {
                ForEach(DeckTab.allCases) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { model.selectedTab = tab }
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 31)
                            .foregroundStyle(model.selectedTab == tab ? Color.white : DeckStyle.secondary)
                            .background(model.selectedTab == tab ? Color.white.opacity(0.1) : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(model.selectedTab == tab ? .isSelected : [])
                }
            }.padding(3).background(Color.white.opacity(0.035), in: Capsule())
            Group {
                switch model.selectedTab {
                case .music: MusicPane(media: model.media)
                case .clipboard: ClipboardPane(model: model, clipboard: model.clipboard, focusRequested: $clipboardSearchRequested)
                case .files: ShelfPane(shelf: model.shelf, preview: model.isPreview)
                case .timer: TimerPane(timer: model.focusTimer)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.selectedTab != .files { dropStrip }
            if let notice = model.notice { DeckNotice(text: notice) }
            if model.isPreview {
                Text("предпросмотр · демонстрационные данные").font(.system(size: 9))
                    .foregroundStyle(DeckStyle.secondary).frame(maxWidth: .infinity)
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(dropTargeted ? DeckStyle.mint.opacity(0.6) : DeckStyle.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .preferredColorScheme(.dark)
            .onDrop(of: DeckDrop.types, isTargeted: $dropTargeted) { DeckDrop.receive($0, model: model) }
            .onExitCommand { model.onClose() }
            .onChange(of: model.clipboardFocusRequest) { _, _ in clipboardSearchRequested = true }
            .background(keyboardCommands)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(".notchdeck").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(-0.5)
            Text("под рукой").font(.system(size: 10)).foregroundStyle(DeckStyle.secondary).padding(.leading, 3)
            Spacer()
            DeckIconButton(symbol: model.pinned ? "pin.fill" : "pin", label: model.pinned ? "Открепить панель" : "Оставить панель открытой", active: model.pinned) { model.pinned.toggle() }
            DeckIconButton(symbol: "slider.horizontal.3", label: "Настройки") { model.onSettings() }
            DeckIconButton(symbol: "xmark", label: "Свернуть панель") { model.onClose() }
        }.frame(height: 27)
    }

    private var dropStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").foregroundStyle(DeckStyle.mint)
            Text(dropTargeted ? "отпусти файлы — они останутся на полке" : "перетащи файлы сюда, чтобы держать их под рукой")
                .font(.system(size: 10)).foregroundStyle(DeckStyle.secondary)
            Spacer(minLength: 0)
            Button { model.selectedTab = .files } label: { Image(systemName: "arrow.up.right").font(.system(size: 10)) }
                .buttonStyle(.plain).help("Открыть полку файлов").accessibilityLabel("Открыть полку файлов")
        }.padding(.horizontal, 12).frame(height: 31)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private var keyboardCommands: some View {
        Group {
            ForEach(Array(DeckTab.allCases.enumerated()), id: \.element.id) { index, tab in
                Button(tab.title) { model.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("Поиск в буфере") { model.onFocusClipboard() }.keyboardShortcut("f", modifiers: .command)
        }.hidden().frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

@MainActor
private struct MusicPane: View {
    @ObservedObject var media: MediaController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(media.sourceName, systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(DeckStyle.secondary)
                    Spacer()
                    Picker("Проигрыватель", selection: $media.source) {
                        ForEach(MediaSource.allCases) { source in Text(source.title).tag(source) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 172).controlSize(.small)
                    DeckIconButton(symbol: "arrow.clockwise", label: "Обновить проигрыватель") { media.refresh() }
                }
                HStack(spacing: 21) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17).fill(Color.white.opacity(0.05))
                        if let icon = media.appIcon {
                            Image(nsImage: icon).resizable().scaledToFit().padding(22)
                        } else {
                            Image(systemName: "waveform").font(.system(size: 36, weight: .light)).foregroundStyle(DeckStyle.mint)
                        }
                    }.frame(width: 100, height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(DeckStyle.line, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(media.title.isEmpty ? "ничего не играет" : media.title)
                            .font(.system(size: 19, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(media.artist.isEmpty ? "запусти трек в выбранном проигрывателе" : media.artist)
                            .font(.system(size: 12)).foregroundStyle(DeckStyle.secondary).lineLimit(2)
                        HStack(spacing: 20) {
                            transport("backward.end.fill", label: "Предыдущий трек", action: media.previous)
                            Button(action: media.togglePlayback) {
                                Image(systemName: media.isPlaying == true ? "pause.fill" : media.isPlaying == false ? "play.fill" : "playpause.fill")
                                    .font(.system(size: 17, weight: .medium)).frame(width: 43, height: 43)
                                    .foregroundStyle(Color.black).background(DeckStyle.mint, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel(media.isPlaying == true ? "Пауза" : media.isPlaying == false ? "Воспроизвести" : "Воспроизвести или поставить на паузу")
                            transport("forward.end.fill", label: "Следующий трек", action: media.next)
                            if media.isBusy { ProgressView().controlSize(.mini).padding(.leading, 3) }
                        }.padding(.top, 5).disabled(media.isBusy || (media.source == .system && !media.systemAccessGranted))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if media.duration > 0 {
                    VStack(spacing: 5) {
                        ProgressView(value: min(media.elapsed, media.duration), total: media.duration).tint(DeckStyle.mint)
                        HStack { Text(time(media.elapsed)); Spacer(); Text(time(media.duration)) }
                            .font(.system(size: 9)).monospacedDigit().foregroundStyle(DeckStyle.secondary)
                    }.accessibilityLabel("Позиция воспроизведения").accessibilityValue("\(time(media.elapsed)) из \(time(media.duration))")
                }
                if media.source == .system && !media.systemAccessGranted {
                    HStack(spacing: 12) {
                        Text("Для системных медиаклавиш нужен доступ к Универсальному доступу.")
                            .font(.system(size: 10)).foregroundStyle(DeckStyle.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Разрешить доступ") { media.requestSystemAccess() }.buttonStyle(DeckActionStyle())
                    }
                }
                if let status = media.status { DeckNotice(text: status) }
            }.padding(15)
        }.modifier(DeckSurface())
    }

    private func transport(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 27, height: 32).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.8)).help(label).accessibilityLabel(label)
    }

    private func time(_ seconds: Double) -> String {
        let seconds = Int(max(0, seconds))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
private struct ClipboardPane: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var clipboard: ClipboardController
    @Binding var focusRequested: Bool
    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        clipboard.items.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }
    }
    private var selected: ClipboardItem? { filtered.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DeckStyle.secondary)
                TextField("найти в истории", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                    .focused($searchFocused).onSubmit { if let selected { clipboard.copy(selected) } }
                    .accessibilityLabel("Поиск в истории буфера")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DeckStyle.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Очистить поиск")
                }
                Menu {
                    Button("Очистить незакреплённое") { clipboard.clear() }
                    Button("Очистить всё, включая закреплённое", role: .destructive) { clipboard.clear(includePinned: true) }
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Очистить историю")
            }.padding(.horizontal, 11).frame(height: 31).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            if !clipboard.enabled && !model.isPreview {
                VStack(spacing: 12) {
                    DeckEmptyState(symbol: "clipboard", title: "история буфера выключена", detail: "включи её, чтобы сохранять текст, изображения и файлы, которые копируешь.")
                    Button("Включить историю") { clipboard.enabled = true }.buttonStyle(DeckActionStyle(prominent: true)).padding(.bottom, 12)
                }.modifier(DeckSurface())
            } else if filtered.isEmpty {
                DeckEmptyState(symbol: "doc.on.clipboard", title: query.isEmpty ? "история пока пуста" : "ничего не найдено", detail: query.isEmpty ? "скопируй текст, изображение или файл — он появится здесь." : "попробуй другое слово или очисти поиск.")
                    .modifier(DeckSurface())
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(filtered) { item in
                            clipboardRow(item).tag(item.id)
                                .contextMenu {
                                    Button("Копировать") { clipboard.copy(item) }
                                    Button(item.isPinned ? "Открепить" : "Закрепить") { clipboard.togglePin(item) }
                                    Button("Удалить из истории", role: .destructive) { clipboard.remove(item) }
                                }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden).frame(width: 190)
                    Rectangle().fill(DeckStyle.line).frame(width: 1)
                    if let selected { clipboardDetail(selected) }
                    else { DeckEmptyState(symbol: "text.alignleft", title: "выбери запись", detail: "содержимое появится здесь целиком.") }
                }.modifier(DeckSurface())
            }
            if let status = clipboard.status { DeckNotice(text: status) }
        }
        .onChange(of: focusRequested) { _, requested in if requested { focusSearch() } }
        .onChange(of: query) { _, _ in if selected == nil { selectedID = filtered.first?.id } }
        .onChange(of: clipboard.items) { _, _ in if selected == nil { selectedID = filtered.first?.id } }
        .onAppear {
            if selectedID == nil { selectedID = filtered.first?.id }
            if focusRequested { focusSearch() }
        }
        .onKeyPress(.return) {
            guard !searchFocused, let selected else { return .ignored }
            clipboard.copy(selected)
            return .handled
        }
    }

    private func focusSearch() {
        // Новая вкладка должна успеть присоединить поле к key window.
        DispatchQueue.main.async {
            guard focusRequested, model.selectedTab == .clipboard else { return }
            searchFocused = true
            DispatchQueue.main.async {
                if searchFocused { focusRequested = false }
            }
        }
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol(item)).font(.system(size: 11)).foregroundStyle(DeckStyle.mint).frame(width: 15).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                Text(item.sourceName).font(.system(size: 9)).foregroundStyle(DeckStyle.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(DeckStyle.mint) }
        }.padding(.vertical, 5).contentShape(Rectangle())
            .onTapGesture(count: 2) { clipboard.copy(item) }
            .accessibilityElement(children: .combine)
    }

    private func clipboardDetail(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.createdAt, style: .time).font(.system(size: 9)).foregroundStyle(DeckStyle.secondary)
                Spacer()
                DeckIconButton(symbol: item.isPinned ? "pin.fill" : "pin", label: item.isPinned ? "Открепить запись" : "Закрепить запись", active: item.isPinned) { clipboard.togglePin(item) }
                DeckIconButton(symbol: "trash", label: "Удалить запись из истории") { clipboard.remove(item) }
                Button("Копировать") { clipboard.copy(item) }.buttonStyle(DeckActionStyle(prominent: true))
            }
            ScrollView {
                Group {
                    switch item.kind {
                    case .text:
                        Text(String((item.text ?? "").prefix(50_000))).font(.system(size: 14))
                            .textSelection(.enabled).lineSpacing(4).frame(maxWidth: .infinity, alignment: .topLeading)
                        if (item.text?.count ?? 0) > 50_000 {
                            Text("показаны первые 50 000 символов · копируется весь текст").font(.system(size: 9)).foregroundStyle(DeckStyle.secondary)
                        }
                    case .image:
                        if let data = item.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).accessibilityLabel("Изображение из буфера")
                        } else { Text("изображение недоступно").foregroundStyle(DeckStyle.secondary) }
                    case .files:
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(item.filePaths, id: \.self) { path in
                                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc")
                                    .font(.system(size: 12)).help(path)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func symbol(_ item: ClipboardItem) -> String {
        switch item.kind { case .text: "text.alignleft"; case .image: "photo"; case .files: "doc.on.doc" }
    }
}

@MainActor
private struct ShelfPane: View {
    @ObservedObject var shelf: FileShelf
    let preview: Bool

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("полка на время").font(.system(size: 12, weight: .medium))
                Text("\(shelf.items.count) / \(shelf.maximum)").font(.system(size: 10)).foregroundStyle(DeckStyle.secondary)
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Убрать всё") { shelf.clear() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(DeckStyle.secondary)
                }
            }
            if shelf.items.isEmpty {
                DeckEmptyState(symbol: "tray.and.arrow.down", title: "перетащи файлы на панель", detail: "потом перетащи их отсюда в Finder или другое приложение. оригиналы остаются на месте.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            HStack(spacing: 10) {
                                Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(item.exists || preview ? item.url.deletingLastPathComponent().path : "файл перемещён или удалён")
                                        .font(.system(size: 9)).foregroundStyle(DeckStyle.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                DeckIconButton(symbol: "arrow.up.right", label: "Показать \(item.name) в Finder") { shelf.reveal(item) }
                                DeckIconButton(symbol: "xmark", label: "Убрать \(item.name) с полки") { shelf.remove(item) }
                            }.padding(9).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                                .onDrag { !preview && item.exists ? NSItemProvider(contentsOf: item.url) ?? NSItemProvider() : NSItemProvider() }
                        }
                    }
                }
                Text("перетаскивай файлы дальше · удаление с полки не удаляет оригинал").font(.system(size: 9)).foregroundStyle(DeckStyle.secondary)
            }
            if let status = shelf.status { DeckNotice(text: status) }
        }.padding(15).modifier(DeckSurface())
    }
}

@MainActor
private struct TimerPane: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                HStack {
                    Label(phaseTitle, systemImage: timer.phase == .finished ? "checkmark.circle" : "timer")
                        .font(.system(size: 11)).foregroundStyle(timer.phase == .running ? DeckStyle.mint : DeckStyle.secondary)
                    Spacer()
                    if timer.phase == .idle || timer.phase == .finished {
                        Stepper("\(timer.selectedMinutes) мин", value: $timer.selectedMinutes, in: 1...240)
                            .font(.system(size: 11)).fixedSize().accessibilityLabel("Длительность таймера в минутах")
                    }
                }
                Text(displayTime)
                    .font(.system(size: 54, weight: .light, design: .rounded)).monospacedDigit().tracking(-2)
                    .foregroundStyle(timer.phase == .finished ? DeckStyle.mint : Color.white)
                    .accessibilityLabel("Осталось времени").accessibilityValue(displayTime)
                if timer.phase == .idle || timer.phase == .finished {
                    HStack(spacing: 8) {
                        ForEach([5, 15, 25, 45], id: \.self) { minutes in
                            Button("\(minutes) мин") { timer.selectedMinutes = minutes }
                                .buttonStyle(DeckActionStyle(prominent: timer.selectedMinutes == minutes))
                        }
                    }
                } else {
                    ProgressView(value: timer.progress).tint(DeckStyle.mint).padding(.horizontal, 34)
                }
                HStack(spacing: 10) {
                    if timer.phase == .running || timer.phase == .paused {
                        Button(timer.phase == .running ? "Пауза" : "Продолжить") { timer.pauseOrResume() }
                            .buttonStyle(DeckActionStyle(prominent: true))
                        Button("Сбросить") { timer.reset() }.buttonStyle(DeckActionStyle())
                    } else {
                        Button(timer.phase == .finished ? "Ещё раз" : "Начать") { timer.start() }
                            .buttonStyle(DeckActionStyle(prominent: true))
                    }
                }
            }.padding(16)
        }.modifier(DeckSurface())
    }

    private var phaseTitle: String {
        switch timer.phase { case .idle: "время для своего дела"; case .running: "идёт отсчёт"; case .paused: "на паузе"; case .finished: "время вышло" }
    }

    private var displayTime: String {
        timer.phase == .idle ? String(format: "%02d:00", timer.selectedMinutes) : timer.formattedRemaining
    }
}
