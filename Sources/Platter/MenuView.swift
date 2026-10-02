import SwiftUI

struct MenuView: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NowPlayingCard(player: player)

            if let blocked = player.blockedSource {
                PermissionNote(source: blocked)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Scene")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(SceneKind.allCases) { kind in
                        SceneTile(kind: kind, selected: prefs.scene == kind) { prefs.scene = kind }
                    }
                }
            }

            VStack(spacing: 8) {
                SettingRow(title: "Room turns to night after 7 PM", isOn: $prefs.roomFollowsClock)
                SettingRow(title: "Hide when paused", isOn: $prefs.hideWhenPaused)
                SettingRow(title: "Launch at login", isOn: $prefs.launchAtLogin)
            }

            Divider()

            HStack {
                Text("Platter 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct NowPlayingCard: View {
    @ObservedObject var player: NowPlayingService

    var body: some View {
        if let track = player.track {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Artwork(image: player.artwork)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(track.source.displayName, systemImage: track.isPlaying ? "waveform" : "pause.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let position = track.position(at: context.date)
                    VStack(spacing: 4) {
                        ProgressBar(value: track.duration > 0 ? position / track.duration : 0)
                        HStack {
                            Text(timeString(position))
                            Spacer()
                            Text("-" + timeString(max(0, track.duration - position)))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 30) {
                    ControlButton(symbol: "backward.fill") { player.send(.previous) }
                    ControlButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 20) { player.send(.playPause) }
                    ControlButton(symbol: "forward.fill") { player.send(.next) }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing")
                        .font(.headline)
                    Text("Play something in Spotify or Apple Music.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct Artwork: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: max(4, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 4)
    }
}

private struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SceneTile: View {
    let kind: SceneKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 18))
                Text(kind.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct PermissionNote: View {
    let source: PlayerSource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Platter can't see \(source.displayName)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Allow it under Privacy & Security → Automation.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}
