import SwiftUI
import SwiftData

struct AddSongView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SongsViewModel

    @State private var searchText = ""
    @State private var manualTitle = ""
    @State private var manualArtist = ""
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(SingCoachTheme.textSecondary)
                        TextField("Search by song title or artist...", text: $searchText)
                            .foregroundColor(SingCoachTheme.textPrimary)
                            .onSubmit {
                                Task { await viewModel.search(query: searchText) }
                            }
                        if viewModel.isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(12)
                    .background(SingCoachTheme.surface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Button {
                        Task { await viewModel.search(query: searchText) }
                    } label: {
                        Text("Search")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(SingCoachTheme.accent)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(SingCoachTheme.destructive)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    // Results
                    if !viewModel.searchResults.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.searchResults) { result in
                                    Button {
                                        Task {
                                            await viewModel.addSong(from: result, modelContext: modelContext)
                                        }
                                    } label: {
                                        SearchResultRow(result: result)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                    } else if !viewModel.isSearching && searchText.isEmpty {
                        // Manual entry option
                        Spacer()
                        Button {
                            showManualEntry.toggle()
                        } label: {
                            Text("Add manually")
                                .font(.system(size: 14))
                                .foregroundColor(SingCoachTheme.textSecondary)
                                .underline()
                        }
                        .padding(.bottom, 20)
                    } else {
                        Spacer()
                    }
                }
            }
            .navigationTitle("Add Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualSongEntryView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SearchResultRow: View {
    let result: LRCLibSearchResult

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.trackName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(SingCoachTheme.textPrimary)
                    .lineLimit(1)
                Text(result.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(SingCoachTheme.textSecondary)
                    .lineLimit(1)
                if let album = result.albumName {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundColor(SingCoachTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            if result.syncedLyrics != nil {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(SingCoachTheme.accent)
            }
        }
        .padding(12)
        .background(SingCoachTheme.surface)
        .cornerRadius(10)
    }
}

struct ManualSongEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SongsViewModel
    @State private var title = ""
    @State private var artist = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField("Song title", text: $title)
                        .textFieldStyle(SingCoachTextFieldStyle())
                    TextField("Artist name", text: $artist)
                        .textFieldStyle(SingCoachTextFieldStyle())

                    Button {
                        viewModel.addManualSong(title: title, artist: artist, modelContext: modelContext)
                        dismiss()
                    } label: {
                        Text("Add Song")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(title.isEmpty || artist.isEmpty ? SingCoachTheme.surface : SingCoachTheme.accent)
                            .foregroundColor(title.isEmpty || artist.isEmpty ? SingCoachTheme.textSecondary : .black)
                            .cornerRadius(12)
                    }
                    .disabled(title.isEmpty || artist.isEmpty)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 24)
                .padding(.horizontal, 16)
            }
            .navigationTitle("Add Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(SingCoachTheme.textSecondary)
                }
            }
        }
    }
}

struct SingCoachTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(SingCoachTheme.surface)
            .foregroundColor(SingCoachTheme.textPrimary)
            .cornerRadius(12)
    }
}
