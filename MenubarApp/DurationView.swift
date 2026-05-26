import SwiftUI

struct DurationView: View {
    @EnvironmentObject private var manager: MenuBarManager

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(HideDuration.allCases.enumerated()), id: \.offset) { idx, dur in
                if idx > 0 { dot }
                durationButton(dur)
            }
            dot
            gearButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 310)
    }

    // MARK: - Subviews

    private func durationButton(_ dur: HideDuration) -> some View {
        let active = manager.hideDuration == dur && manager.hideMode != .off
        return ZStack {
            Circle()
                .fill(active ? Color.accentColor : Color(NSColor.controlColor))
                .frame(width: 24, height: 24)
            Group {
                if dur == .forever {
                    Image(systemName: "infinity")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(dur.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(active ? .white : .primary)
        }
        .contentShape(Circle())
        .onTapGesture { manager.setHideDuration(dur) }
        .frame(maxWidth: .infinity)
    }

    private var gearButton: some View {
        ZStack {
            Circle()
                .fill(Color(NSColor.controlColor))
                .frame(width: 24, height: 24)
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var dot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 3, height: 3)
    }
}

#Preview {
    DurationView()
        .environmentObject(MenuBarManager.preview)
}
