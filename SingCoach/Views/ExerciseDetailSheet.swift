import SwiftUI
import WebKit

struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let onMarkPracticed: () -> Void
    @State private var practiced = false
    @State private var showPracticeTools = false

    var body: some View {
        NavigationStack {
            ZStack {
                SingCoachTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                CategoryBadge(category: exercise.category)
                                DifficultyBadge(difficulty: exercise.difficulty)
                                Text("\(exercise.durationMinutes) min")
                                    .font(.system(size: 11))
                                    .foregroundColor(SingCoachTheme.textSecondary)
                            }

                            Text(exercise.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(SingCoachTheme.textPrimary)

                            Text(exercise.focusArea)
                                .font(.system(size: 14))
                                .foregroundColor(SingCoachTheme.accent)
                        }

                        Divider()
                            .overlay(SingCoachTheme.surface)

                        // Description
                        SectionCard(title: "About") {
                            Text(exercise.exerciseDescription)
                                .font(.system(size: 15))
                                .foregroundColor(SingCoachTheme.textPrimary)
                                .lineSpacing(4)
                        }

                        // Instruction
                        SectionCard(title: "How to Do It") {
                            Text(exercise.instruction)
                                .font(.system(size: 15))
                                .foregroundColor(SingCoachTheme.textPrimary)
                                .lineSpacing(4)
                        }

                        // Tips
                        if !exercise.tips.isEmpty {
                            SectionCard(title: "Tips") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(exercise.tips, id: \.self) { tip in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(SingCoachTheme.accent)
                                                .font(.system(size: 14))
                                                .padding(.top, 2)
                                            Text(tip)
                                                .font(.system(size: 14))
                                                .foregroundColor(SingCoachTheme.textPrimary)
                                        }
                                    }
                                }
                            }
                        }

                        // YouTube video — inline embed via loadHTMLString (fixes Error 153)
                        if let youtubeURL = exercise.youtubeURL {
                            SectionCard(title: "Watch a Demo") {
                                YouTubeWebView(urlString: youtubeURL)
                                    .frame(height: 220)
                                    .cornerRadius(10)
                                    .clipped()
                            }
                        }

                        // Practice button
                        Button {
                            showPracticeTools = true
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Practice")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(SingCoachTheme.accent)
                            .foregroundColor(.black)
                            .cornerRadius(14)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(SingCoachTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPracticeTools) {
            PracticeToolsView(exercise: exercise)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SingCoachTheme.accent)
            content
        }
        .padding(14)
        .background(SingCoachTheme.surface)
        .cornerRadius(12)
    }
}

/// Inline YouTube embed using youtube-nocookie.com + explicit origin parameter.
///
/// Error history:
///  Error 153 — DOM origin mismatch → fixed by loadHTMLString with baseURL (Build 9)
///  Error 152 — embed URL origin check → fixed by youtube-nocookie.com + origin= param (Build 29)
///
/// youtube-nocookie.com is YouTube's official privacy-preserving embed domain.
/// It skips consent/cookie checks that cause error 152 on the standard domain,
/// and accepts the origin= parameter to satisfy its own origin validation.
struct YouTubeWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Use persistent data store so the player can cache session data between views
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let videoID = extractVideoID(from: urlString) else { return }
        let (html, baseURL) = YouTubeWebView.embedHTML(for: videoID)
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Exposed for testing — returns the embed HTML and baseURL for a given video ID.
    static func embedHTML(for videoID: String) -> (html: String, baseURL: URL?) {
        // origin= must match the baseURL domain — both set to youtube-nocookie.com
        let embedURL = "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&enablejsapi=1&origin=https://www.youtube-nocookie.com"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { margin: 0; padding: 0; background: #000; }
          iframe { width: 100%; height: 100vh; border: none; }
        </style>
        </head>
        <body>
        <iframe
          src="\(embedURL)"
          allow="autoplay; encrypted-media"
          allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin">
        </iframe>
        </body>
        </html>
        """
        // baseURL matches the origin= parameter above — player sees a consistent trusted origin
        return (html, URL(string: "https://www.youtube-nocookie.com"))
    }

    private func extractVideoID(from urlString: String) -> String? {
        if urlString.contains("watch?v=") {
            return URLComponents(string: urlString)?.queryItems?.first(where: { $0.name == "v" })?.value
        } else if urlString.contains("youtu.be/") {
            return URL(string: urlString)?.lastPathComponent
        }
        // Already an embed URL — pull the ID from the path
        if urlString.contains("/embed/") {
            return URL(string: urlString)?.lastPathComponent
        }
        return nil
    }
}
