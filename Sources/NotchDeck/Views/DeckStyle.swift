import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DeckStyle {
    static let mint = Color(red: 0.63, green: 0.92, blue: 0.79)
    static let secondary = Color.white.opacity(0.52)
    static let line = Color.white.opacity(0.08)
}

struct DeckSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 15

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: radius).fill(Color(white: 0.07))
            } else {
                RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.44), in: RoundedRectangle(cornerRadius: radius))
            }
        }.overlay(RoundedRectangle(cornerRadius: radius).stroke(DeckStyle.line, lineWidth: 1))
    }
}

struct DeckIconButton: View {
    let symbol: String
    let label: String
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? DeckStyle.mint : Color.white.opacity(0.62))
                .frame(width: 29, height: 29)
                .background(active ? DeckStyle.mint.opacity(0.12) : Color.white.opacity(0.045), in: Circle())
                .contentShape(Circle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct DeckActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).frame(height: 30)
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.85))
            .background(prominent ? DeckStyle.mint : Color.white.opacity(0.08), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DeckEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 27, weight: .light))
                .foregroundStyle(DeckStyle.mint.opacity(0.8)).padding(.bottom, 3)
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            Text(detail).font(.system(size: 11)).foregroundStyle(DeckStyle.secondary)
                .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeckNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle").font(.system(size: 10))
            .foregroundStyle(Color.orange.opacity(0.9)).lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum DeckDrop {
    static let types = [UTType.fileURL.identifier]

    static func receive(_ providers: [NSItemProvider], model: DeckModel) -> Bool {
        guard !model.isPreview else { return false }
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        model.selectedTab = .files
        if !model.expanded { model.onToggle() }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak model] item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else if let value = item as? String { url = URL(string: value) }
                else { url = nil }
                guard let url, url.isFileURL else { return }
                Task { @MainActor [weak model] in model?.shelf.add([url]) }
            }
        }
        return true
    }
}
