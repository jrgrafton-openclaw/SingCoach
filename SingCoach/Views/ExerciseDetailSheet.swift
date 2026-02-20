import SwiftUI
import WebKit

struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let onMarkPracticed: () -> Void
    @State private var practiced = false

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

                        // YouTube video
                        if let youtubeURL = exercise.youtubeURL {
                            SectionCard(title: "Watch a Demo") {
                                YouTubeWebView(urlString: youtubeURL)
                                    .frame(height: 220)
                                    .cornerRadius(10)
                            }
                        }

                        // Mark as practiced
                        Button {
                            practiced = true
                            onMarkPracticed()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: practiced ? "checkmark.circle.fill" : "flame.fill")
                                Text(practiced ? "Practised!" : "Mark as Practised Today")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(practiced ? Color.green : SingCoachTheme.accent)
                            .foregroundColor(practiced ? .white : .black)
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

struct YouTubeWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: urlString) else { return }
        // Convert to embed URL if it's a regular YouTube URL
        let embedURL = youtubeEmbedURL(from: urlString) ?? url
        let request = URLRequest(url: embedURL)
        webView.load(request)
    }

    private func youtubeEmbedURL(from urlString: String) -> URL? {
        if urlString.contains("youtube.com/watch?v=") {
            if let videoID = URLComponents(string: urlString)?.queryItems?.first(where: { $0.name == "v" })?.value {
                return URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1")
            }
        } else if urlString.contains("youtu.be/") {
            if let videoID = URL(string: urlString)?.lastPathComponent {
                return URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1")
            }
        }
        return URL(string: urlString)
    }
}
