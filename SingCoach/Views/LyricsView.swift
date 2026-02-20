import SwiftUI

struct LyricsView: View {
    let song: Song
    @State private var currentTimestamp: Double = 0

    var lines: [LyricsLine] {
        song.sortedLyricsLines
    }

    var body: some View {
        Group {
            if lines.isEmpty {
                EmptyStateView(
                    icon: "text.alignleft",
                    title: "No Lyrics",
                    subtitle: "Lyrics will appear here when found"
                )
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            LyricLineView(line: line, currentTimestamp: currentTimestamp)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

struct LyricLineView: View {
    let line: LyricsLine
    let currentTimestamp: Double

    var state: LyricState {
        guard let ts = line.timestampSeconds else { return .current }
        if ts <= currentTimestamp { return .past }
        return .future
    }

    var body: some View {
        Group {
            if let section = line.section {
                Text(section.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
            }

            Text(line.text)
                .font(SingCoachTheme.lyricFont())
                .lineSpacing(8)
                .foregroundColor(state.color)
                .scaleEffect(state.scale, anchor: .leading)
                .padding(.vertical, 6)
                .animation(.easeInOut(duration: 0.3), value: state)
        }
    }
}

enum LyricState: Equatable {
    case past, current, future

    var color: Color {
        switch self {
        case .past: return SingCoachTheme.textPrimary.opacity(0.4)
        case .current: return SingCoachTheme.accent
        case .future: return SingCoachTheme.textPrimary.opacity(0.7)
        }
    }

    var scale: CGFloat {
        switch self {
        case .current: return 1.05
        default: return 1.0
        }
    }
}
