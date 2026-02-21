import SwiftUI

struct LyricsView: View {
    let song: Song
    @State private var currentTimestamp: Double = 0

    var lines: [LyricsLine] {
        song.sortedLyricsLines
    }

    /// Compute which line indices should have a paragraph break BEFORE them.
    ///
    /// Always runs ALL detection methods and merges them — never short-circuits on stored markers.
    /// This ensures existing songs saved with incomplete parse data still display correctly.
    ///
    /// Methods (all run, results merged):
    ///   A. Stored section markers ("¶" or named) set during LRC/plain parse
    ///   B. Repeated-block: 3-line blocks appearing 2+ times (chorus/verse detection)
    ///   C. Timestamp gap: gap ≥ 1.8× median AND ≥ 6s absolute
    ///
    /// Consecutive breaks are collapsed to one (keep first of each run).
    var paragraphBreakIndices: Set<Int> {
        guard lines.count > 1 else { return [] }

        var rawBreaks = Set<Int>()

        // A. Stored section markers (from LRC/plain parse)
        for (i, line) in lines.enumerated() where i > 0 && line.section != nil {
            rawBreaks.insert(i)
        }

        // B. Repeated-block detection
        // Find every 3-line fingerprint that appears at 2+ non-overlapping positions.
        // Mark the start of each occurrence (including first) as a paragraph boundary.
        let BLOCK = 3
        if lines.count >= BLOCK {
            var firstSeen: [String: Int] = [:]
            var blockStarts = Set<Int>()

            for i in 0...(lines.count - BLOCK) {
                let fp = (0..<BLOCK).map { j in
                    lines[i + j].text.lowercased()
                        .components(separatedBy: .alphanumerics.inverted)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }.joined(separator: "|")

                if let prev = firstSeen[fp] {
                    if i >= prev + BLOCK {
                        blockStarts.insert(prev)
                        blockStarts.insert(i)
                    }
                } else {
                    firstSeen[fp] = i
                }
            }
            for pos in blockStarts where pos > 0 {
                rawBreaks.insert(pos)
            }
        }

        // C. Timestamp gap fallback (catches bridges / intros with unique text)
        let hasSynced = lines.contains { $0.timestampSeconds != nil }
        if hasSynced {
            let timestamps = lines.compactMap { $0.timestampSeconds }
            if timestamps.count > 2 {
                let gaps = zip(timestamps, timestamps.dropFirst()).map { $1 - $0 }
                let median = gaps.sorted()[gaps.count / 2]
                let threshold = max(6.0, median * 1.8)
                for i in 1..<lines.count {
                    guard let t1 = lines[i - 1].timestampSeconds,
                          let t2 = lines[i].timestampSeconds else { continue }
                    if t2 - t1 >= threshold { rawBreaks.insert(i) }
                }
            }
        }

        // Collapse consecutive breaks — keep only the first of each run
        let sorted = rawBreaks.sorted()
        var result = Set<Int>()
        var prev = -99
        for b in sorted {
            if b - prev > 1 { result.insert(b) }
            prev = b
        }
        return result
    }

    /// Returns the effective section label for a line (for named-section display).
    func sectionLabel(for line: LyricsLine) -> String? {
        guard let section = line.section, section != "¶" else { return nil }
        return section
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
                let breaks = paragraphBreakIndices
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            let isBreak = breaks.contains(index)
                            let namedSection = sectionLabel(for: line)

                            if isBreak {
                                if let sectionName = namedSection {
                                    // Named section header (VERSE, CHORUS, BRIDGE, etc.)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sectionName.uppercased())
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(SingCoachTheme.accent)
                                            .tracking(1.2)
                                        Rectangle()
                                            .fill(SingCoachTheme.accent)
                                            .frame(height: 1)
                                            .frame(maxWidth: 40)
                                    }
                                    .padding(.top, 32)
                                    .padding(.bottom, 10)
                                } else {
                                    // Unnamed paragraph break: spacer + subtle divider
                                    VStack(spacing: 0) {
                                        Spacer().frame(height: 22)
                                        Rectangle()
                                            .fill(SingCoachTheme.accent.opacity(0.15))
                                            .frame(height: 1)
                                        Spacer().frame(height: 10)
                                    }
                                }
                            }

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
        Text(line.text)
            .font(SingCoachTheme.lyricFont())
            .foregroundColor(state.color)
            .scaleEffect(state.scale, anchor: .leading)
            .padding(.vertical, 7)
            .animation(.easeInOut(duration: 0.3), value: state)
            .frame(maxWidth: .infinity, alignment: .leading)
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
