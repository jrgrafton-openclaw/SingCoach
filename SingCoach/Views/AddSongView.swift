import SwiftUI
import SwiftData

struct AddSongView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SongsViewModel

    @State private var searchText = ""
    @State private var showManualEntry = false
    @FocusState private var isSearchFocused: Bool

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearchFocused = false
        Task { await viewModel.search(query: query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar — search on submit or button tap only (no live/debounce)
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(SingCoachTheme.textSecondary)
                            TextField("Song title or artist...", text: $searchText)
                                .foregroundColor(SingCoachTheme.textPrimary)
                                .autocorrectionDisabled()
                                .focused($isSearchFocused)
                                .onSubmit { performSearch() }
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    viewModel.searchResults = []
                                    viewModel.errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(SingCoachTheme.textSecondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(SingCoachTheme.surface)
                        .cornerRadius(12)

                        // Search button
                        Button(action: performSearch) {
                            if viewModel.isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                                    .frame(width: 44, height: 44)
                                    .background(SingCoachTheme.accent)
                                    .cornerRadius(12)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                                                ? SingCoachTheme.surface
                                                : SingCoachTheme.accent)
                                    .foregroundColor(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                                                     ? SingCoachTheme.textSecondary
                                                     : .black)
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

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
                    } else if !viewModel.isSearching && !searchText.isEmpty && viewModel.searchResults.isEmpty {
                        Spacer()
                        Text("No results for \"\(searchText)\"")
                            .font(.system(size: 14))
                            .foregroundColor(SingCoachTheme.textSecondary)
                        Button {
                            showManualEntry.toggle()
                        } label: {
                            Text("Add manually instead")
                                .font(.system(size: 14))
                                .foregroundColor(SingCoachTheme.accent)
                                .underline()
                        }
                        .padding(.top, 8)
                        Spacer()
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
