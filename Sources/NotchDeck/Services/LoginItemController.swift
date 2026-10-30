import Combine
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status: String?
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        if !preview { refresh() }
    }

    func refresh() {
        guard !preview else { return }
        let state = SMAppService.mainApp.status
        enabled = state == .enabled || state == .requiresApproval
        status = state == .requiresApproval ? "Разреши NotchDeck в Настройках системы → Основные → Объекты входа" : nil
    }

    func setEnabled(_ value: Bool) {
        guard !preview else { return }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            status = "Не удалось изменить автозапуск. Перемести приложение в /Applications и повтори."
        }
    }
}
