import SwiftUI
import SwiftData

struct SongsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]
    @StateObject private var viewModel = SongsViewModel()

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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(songs) { song in
                                NavigationLink(destination: SongDetailView(song: song)) {
                                    SongRowView(song: song)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
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
}

struct SongRowView: View {
    let song: Song

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SingCoachTheme.primaryGradient)
                    .frame(width: 52, height: 52)
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(SingCoachTheme.accent)
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
}
