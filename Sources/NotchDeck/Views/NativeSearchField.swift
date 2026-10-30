import AppKit
import SwiftUI

@MainActor
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var wantsFocus: Bool
    var onSubmit: () -> Void
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> FocusableSearchTextField {
        let field = FocusableSearchTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: "найти в истории",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 12)]
        )
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("Поиск в истории буфера")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field
        field.onWindowAttached = { [weak coordinator = context.coordinator] in coordinator?.requestFocusIfNeeded() }
        return field
    }

    func updateNSView(_ field: FocusableSearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.requestFocusIfNeeded()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusableSearchTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 20)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSearchField
        weak var field: FocusableSearchTextField?
        private var focusScheduled = false

        init(parent: NativeSearchField) { self.parent = parent }

        func requestFocusIfNeeded() {
            guard parent.wantsFocus, field?.window != nil, !focusScheduled else { return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusScheduled = false
                guard self.parent.wantsFocus, let field = self.field,
                      let window = field.window, window.isKeyWindow else { return }
                // Запрос потребляется только после принятия фокуса настоящим NSWindow.
                if window.makeFirstResponder(field) {
                    field.selectText(nil)
                    self.parent.wantsFocus = false
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.onEditingChanged(true) }
        func controlTextDidEndEditing(_ notification: Notification) { parent.onEditingChanged(false) }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

@MainActor
final class FocusableSearchTextField: NSTextField {
    var onWindowAttached: (() -> Void)?
    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
        guard let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWindowAttached?() }
        }
        onWindowAttached?()
    }

    deinit {
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
    }
}
