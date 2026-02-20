import SwiftUI

enum SingCoachTheme {
    // Backgrounds
    static let background = Color(hex: "#0E0918")
    static let gradientStart = Color(hex: "#1A0A2E")
    static let gradientEnd = Color(hex: "#2D1B5E")
    static let surface = Color(hex: "#1C1130")

    // Text
    static let textPrimary = Color(hex: "#F5F0FF")
    static let textSecondary = Color(hex: "#8B7AAA")

    // Accent
    static let accent = Color(hex: "#F5A623")

    // Destructive
    static let destructive = Color(hex: "#FF453A")

    // Gradients
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // Typography
    static func lyricFont() -> Font {
        .system(size: 20, weight: .regular, design: .default)
    }

    static func headerFont() -> Font {
        .system(size: 28, weight: .bold, design: .default)
    }

    static func bodyFont() -> Font {
        .system(size: 16, weight: .regular, design: .default)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
