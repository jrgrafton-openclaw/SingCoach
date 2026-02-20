import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            SongsListView()
                .tabItem {
                    Label("Songs", systemImage: "music.note.list")
                }

            PracticeView()
                .tabItem {
                    Label("Practice", systemImage: "flame.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(SingCoachTheme.accent)
    }
}
