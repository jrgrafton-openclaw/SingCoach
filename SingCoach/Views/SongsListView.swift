import SwiftUI
import SwiftData

struct SongsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]
    @StateObject private var viewModel = SongsViewModel()
    @State private var selectedSong: Song? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                if songs.isEmpty {
                    EmptyStateView(
                        icon: "music.mic",
                        title: "No Songs Yet",
                        subtitle: "Add a song to start practising"
                    )
                } else {
                    // Use List so swipeActions work reliably (NavigationLink inside LazyVStack
                    // consumes the swipe gesture — List handles it natively)
                    List {
                        ForEach(songs) { song in
                            SongRowView(song: song)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedSong = song }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteSong(song)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowBackground(SingCoachTheme.background)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .navigationDestination(item: $selectedSong) { song in
                        SongDetailView(song: song)
                    }
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(SingCoachTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                AddSongView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }

    func deleteSong(_ song: Song) {
        for lesson in song.lessons {
            if let url = URL(string: lesson.audioFileURL) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        modelContext.delete(song)
        try? modelContext.save()
    }
}

struct SongRowView: View {
    let song: Song

    var body: some View {
        HStack(spacing: 14) {
            // Show artwork if available, placeholder otherwise
            if let artworkURL = song.artworkURL, let url = URL(string: artworkURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    case .failure, .empty:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SingCoachTheme.textPrimary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .lineLimit(1)
                if !song.lessons.isEmpty {
                    Text("\(song.lessons.count) lesson\(song.lessons.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(SingCoachTheme.accent)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SingCoachTheme.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SingCoachTheme.surface)
        )
    }

    var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SingCoachTheme.primaryGradient)
                .frame(width: 52, height: 52)
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(SingCoachTheme.accent)
        }
    }
}
