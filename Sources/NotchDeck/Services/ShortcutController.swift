import Carbon
import Foundation

final class ShortcutController {
    var onToggle: () -> Void = {}
    var onClipboard: () -> Void = {}
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []

    func register() -> Bool {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let controller = Unmanaged<ShortcutController>.fromOpaque(pointer).takeUnretainedValue()
            if identifier.id == 1 { controller.onToggle() }
            if identifier.id == 2 { controller.onClipboard() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        for (id, key) in [(UInt32(1), UInt32(kVK_Space)), (UInt32(2), UInt32(kVK_ANSI_V))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey),
                                            EventHotKeyID(signature: 0x4E44434B, id: id),
                                            GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else { unregister(); return false }
            references.append(reference)
        }
        return true
    }

    func unregister() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }
}
