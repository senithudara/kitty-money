import SwiftUI
import UIKit

/// Rounded square showing an item's logo, or its initial on a colored tile when there's no logo yet.
struct LogoTile: View {
    let name: String
    var colorHex: String = "#3A3A42"
    var logoData: Data? = nil
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Group {
            if let logoData, let image = UIImage(data: logoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
                    .frame(width: size, height: size)
                    .background(Color.white, in: shape)
                    .overlay(shape.strokeBorder(Theme.separator, lineWidth: 0.5))
            } else {
                Text(Self.initial(of: name))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color(hex: colorHex), in: shape)
            }
        }
        .accessibilityHidden(true)
    }

    static func initial(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }
}

/// Small square tile with a category's two-letter label.
struct CategoryTile: View {
    let mono: String
    var size: CGFloat = 36

    var body: some View {
        Text(mono)
            .font(.system(size: size * 0.33, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .frame(width: size, height: size)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}
