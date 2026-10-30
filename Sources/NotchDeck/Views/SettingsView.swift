import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var clipboard: ClipboardController
    @StateObject private var login: LoginItemController

    init(model: DeckModel) {
        self.model = model
        settings = model.settings
        clipboard = model.clipboard
        _login = StateObject(wrappedValue: LoginItemController(preview: model.isPreview))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(".notchdeck").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.8)
                    Spacer()
                    Text("всё нужное — под рукой").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
                if model.isPreview { Text("Предпросмотр. Изменения не затрагивают системные настройки.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Панель") {
                Picker("Дисплей", selection: $settings.selectedDisplayID) {
                    Text("Автоматически — экран с камерой").tag(UInt32?.none)
                    ForEach(model.displays) { display in
                        Text(display.name + (display.hasCamera ? " · с камерой" : "")).tag(Optional(display.id))
                    }
                }
                Toggle("Открывать при наведении", isOn: $settings.opensOnHover)
                Toggle("Показывать поверх полноэкранных приложений", isOn: $settings.showsInFullScreen)
                Toggle("Открывать при входе в macOS", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if let status = login.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Toggle("Глобальные сочетания клавиш", isOn: $settings.shortcutsEnabled)
                shortcut("Открыть или свернуть", keys: "⌃ ⌥ Пробел")
                shortcut("Поиск в буфере", keys: "⌃ ⌥ V")
                shortcut("Разделы открытой панели", keys: "⌘ 1 — 4")
                shortcut("Поиск в открытой панели", keys: "⌘ F")
                shortcut("Свернуть открытую панель", keys: "Esc")
            } header: { Text("Клавиатура") } footer: {
                Text("При наведении панель не забирает фокус. Клик или сочетание клавиш позволяет работать с ней с клавиатуры.")
            }
            Section {
                Toggle("История буфера обмена", isOn: $clipboard.enabled)
                Toggle("Сохранять историю между запусками", isOn: $clipboard.persistsHistory).disabled(!clipboard.enabled)
                Stepper("Хранить до \(clipboard.maxItems) записей", value: $clipboard.maxItems, in: 10...5000, step: 10).disabled(!clipboard.enabled)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Не сохранять из приложений").font(.system(size: 12))
                    TextField("com.example.app, com.example.private", text: $clipboard.excludedBundleIDs, axis: .vertical)
                        .font(.system(size: 11, design: .monospaced)).lineLimit(2...4)
                    Text("Идентификаторы приложений через запятую. Записи из этих приложений исключаются из истории.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(!clipboard.enabled)
                if let status = clipboard.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Menu("Очистить историю…") {
                    Button("Незакреплённые записи") { clipboard.clear() }
                    Button("Всё, включая закреплённое", role: .destructive) { clipboard.clear(includePinned: true) }
                }.disabled(clipboard.items.isEmpty)
            } header: { Text("Буфер обмена") } footer: {
                Text("Выключение очищает историю, включая закреплённое. Без сохранения между запусками записи остаются только в памяти до выхода. При сохранении история шифруется, ключ хранится в Связке ключей macOS. При уменьшении лимита старые записи удаляются; закреплённые — последними. Общий объём истории ограничен 64 МиБ.")
            }
            Section("Таймер") { Toggle("Звук по окончании", isOn: $settings.timerSound) }
            Section {
                Text("Полка хранит ссылки на файлы до выхода из приложения. Удаление с полки не удаляет оригиналы.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(minWidth: 500, idealWidth: 540, minHeight: 560, idealHeight: 700)
            .tint(DeckStyle.mint).preferredColorScheme(.dark)
            .onAppear { login.refresh() }
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        HStack { Text(title).font(.system(size: 11)); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
    }
}
