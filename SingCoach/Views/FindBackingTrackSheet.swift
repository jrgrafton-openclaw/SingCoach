import SwiftUI
import MusicKit
import SwiftData

/// Sheet for searching Apple Music catalog for a karaoke/backing track.
/// Uses full MusicKit (now that the entitlement is active on com.jrgrafton.singcoach).
/// Note: All MusicKit.Song references use the fully qualified name to avoid ambiguity
/// with the SwiftData Song model.
struct FindBackingTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let song: Song  // SwiftData Song model

    @StateObject private var musicKit = MusicKitService.shared
    @State private var searchText = ""
    @State private var searchResults: [MusicKit.Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    authorizationBanner

                    // Search field (only shown when authorized)
                    if musicKit.authorizationStatus == .authorized {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(SingCoachTheme.textSecondary)
                            TextField("Search for karaoke track...", text: $searchText)
                                .foregroundColor(SingCoachTheme.textPrimary)
                                .onSubmit {
                                    debounceTask?.cancel()
                                    Task { await performSearch(query: searchText) }
                                }
                                .onChange(of: searchText) { _, newValue in
                                    debounceTask?.cancel()
                                    guard newValue.count >= 2 else {
                                        if newValue.isEmpty { searchResults = [] }
                                        return
                                    }
                                    debounceTask = Task {
                                        try? await Task.sleep(for: .milliseconds(400))
                                        guard !Task.isCancelled else { return }
                                        await performSearch(query: newValue)
                                    }
                                }
                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(SingCoachTheme.accent)
                            } else if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(SingCoachTheme.textSecondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(SingCoachTheme.surface)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(SingCoachTheme.destructive)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        if searchResults.isEmpty && !isSearching && searchText.isEmpty {
                            // Pre-fill with song title + "karaoke"
                            Spacer()
                            Text("Search for \"\(song.title) karaoke\" to find a backing track")
                                .font(.system(size: 14))
                                .foregroundColor(SingCoachTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button {
                                searchText = "\(song.title) \(song.artist) karaoke"
                            } label: {
                                Text("Search for this song")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SingCoachTheme.accent)
                            }
                            .padding(.top, 8)
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(searchResults, id: \.id) { result in
                                        MusicKitSearchResultRow(kitSong: result)
                                            .onTapGesture {
                                                selectTrack(result)
                                            }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
            }
            .navigationTitle("Find Backing Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                if musicKit.authorizationStatus == .notDetermined {
                    // Brief delay to avoid race with sheet presentation animation
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await musicKit.requestAuthorization()
                }
            }
        }
    }

    // MARK: - Authorization Banner

    @ViewBuilder
    var authorizationBanner: some View {
        switch musicKit.authorizationStatus {
        case .denied, .restricted:
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundColor(SingCoachTheme.accent)
                Text("Apple Music Access Required")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textPrimary)
                Text("Go to Settings → SingCoach → Allow Apple Music to search for backing tracks.")
                    .font(.system(size: 14))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(SingCoachTheme.accent)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
        case .notDetermined:
            VStack(spacing: 8) {
                ProgressView()
                    .tint(SingCoachTheme.accent)
                Text("Requesting Apple Music access…")
                    .font(.system(size: 13))
                    .foregroundColor(SingCoachTheme.textSecondary)
            }
            .padding(.top, 60)
        case .authorized:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Actions

    func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            searchResults = try await MusicKitService.shared.searchSongs(query: query)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }

    func selectTrack(_ result: MusicKit.Song) {
        song.karaokeTrackID = result.id.rawValue
        song.karaokeTrackTitle = result.title
        // NOTE: Do NOT overwrite artworkURL — that always comes from the original song's
        // Apple Music metadata (set by autoFetchAppleMusicMetadata in SongsViewModel).
        // The karaoke track may be a different album/cover art entirely.
        try? modelContext.save()
        print("[FindBackingTrack] Linked karaoke track: \(result.title) (\(result.id.rawValue))")
        dismiss()
    }
}

// MARK: - MusicKit Search Result Row

struct MusicKitSearchResultRow: View {
    let kitSong: MusicKit.Song  // Named kitSong to avoid any ambiguity in the compiler

    var body: some View {
        HStack(spacing: 12) {
            // Artwork from MusicKit
            if let artwork = kitSong.artwork {
                ArtworkImage(artwork, width: 52)
                    .cornerRadius(8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SingCoachTheme.primaryGradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(SingCoachTheme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kitSong.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(SingCoachTheme.textPrimary)
                    .lineLimit(1)
                Text(kitSong.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .lineLimit(1)
                if let duration = kitSong.duration {
                    Text(formatDuration(duration))
                        .font(.system(size: 11))
                        .foregroundColor(SingCoachTheme.textSecondary.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: "plus.circle")
                .font(.system(size: 22))
                .foregroundColor(SingCoachTheme.accent)
        }
        .padding(12)
        .background(SingCoachTheme.surface)
        .cornerRadius(10)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
