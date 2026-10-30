import AppKit
import SwiftUI

@MainActor
struct CompactView: View {
    @ObservedObject var model: DeckModel
    @State private var dropTargeted = false

    var body: some View {
        Button { model.onToggle() } label: {
            HStack(spacing: 0) {
                CompactMediaWing(media: model.media, dropTargeted: dropTargeted).frame(width: 32)
                if model.geometry?.hasCamera == true {
                    Color.clear.frame(width: model.geometry?.cameraWidth ?? 0)
                } else {
                    Text("notchdeck").font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68)).frame(maxWidth: .infinity)
                }
                CompactTimerWing(timer: model.focusTimer).frame(width: 32)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black).contentShape(Rectangle())
        }.buttonStyle(.plain).background(Color.black)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 11, bottomTrailingRadius: 11, topTrailingRadius: 0))
            .overlay(alignment: .bottom) { if dropTargeted { Capsule().fill(DeckStyle.mint).frame(height: 2).padding(.horizontal, 11) } }
            .help("Открыть notchdeck · ⌃⌥Пробел").accessibilityLabel("Открыть панель notchdeck")
            .onDrop(of: DeckDrop.types, isTargeted: $dropTargeted) { DeckDrop.receive($0, model: model) }
            .preferredColorScheme(.dark)
    }
}

@MainActor
private struct CompactMediaWing: View {
    @ObservedObject var media: MediaController
    let dropTargeted: Bool

    var body: some View {
        Group {
            if dropTargeted {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 11)).foregroundStyle(DeckStyle.mint)
            } else if media.isPlaying == true {
                Image(systemName: "waveform").font(.system(size: 12, weight: .medium)).foregroundStyle(DeckStyle.mint)
            } else {
                Image(systemName: "circle.grid.2x2.fill").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
            }
        }.accessibilityHidden(true)
    }
}

@MainActor
private struct CompactTimerWing: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        Group {
            if timer.phase == .running || timer.phase == .paused {
                Text(timer.formattedRemaining).font(.system(size: 8, weight: .medium)).monospacedDigit()
                    .foregroundStyle(timer.phase == .running ? DeckStyle.mint : Color.white.opacity(0.5))
                    .minimumScaleFactor(0.7).lineLimit(1)
            } else if timer.phase == .finished {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(DeckStyle.mint)
            } else {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium)).foregroundStyle(Color.white.opacity(0.4))
            }
        }.accessibilityHidden(true)
    }
}
