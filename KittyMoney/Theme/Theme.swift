import SwiftUI
import UIKit

/// Graphite and lime design tokens. Every color adapts to light and dark mode.
enum Theme {
    // Surfaces
    static let background = Color(light: "#F4F4F1", dark: "#0C0C0E")
    static let card = Color(light: "#FFFFFF", dark: "#19191D")
    static let cardRaised = Color(light: "#EDEDE9", dark: "#26262C")
    static let track = Color(light: "#E4E4DF", dark: "#2A2A30")
    static let tabBar = Color(light: "#FFFFFF", dark: "#121215")
    static let separator = Color(light: "#E2E2DD", dark: "#26262C")

    // Text
    static let textPrimary = Color(light: "#18181B", dark: "#F2F2F0")
    static let textSecondary = Color(light: "#6B6B70", dark: "#9A9AA0")

    // Brand
    /// Lime used as a fill (buttons, the balance card). Text on it uses `onLime`.
    static let lime = Color(hex: "#C6F432")
    static let onLime = Color(hex: "#0C0C0E")
    /// Lime used as text or an icon tint. Darker in light mode so it stays readable.
    static let accentText = Color(light: "#4F6B00", dark: "#C6F432")

    // Meaning
    static let warning = Color(light: "#A35F00", dark: "#F0B44C")
    static let danger = Color(light: "#C8372D", dark: "#FF7A6B")

    // Shape
    static let radiusLarge: CGFloat = 24
    static let radiusMedium: CGFloat = 20
    static let radiusSmall: CGFloat = 14
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that switches with the system (or app-chosen) appearance.
    init(light: String, dark: String) {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Shared view styling

struct CardBackground: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = Theme.radiusMedium, padding: CGFloat = 16) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}
