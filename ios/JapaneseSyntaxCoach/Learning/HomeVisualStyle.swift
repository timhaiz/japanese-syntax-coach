import SwiftUI

/// Matches the existing Web design tokens in app/design-tokens.css.
enum HomeVisualStyle {
    static let canvas = Color(red: 247.0 / 255, green: 248.0 / 255, blue: 245.0 / 255)
    static let card = Color.white
    static let ink = Color(red: 23.0 / 255, green: 33.0 / 255, blue: 43.0 / 255)
    static let secondaryInk = Color(red: 113.0 / 255, green: 128.0 / 255, blue: 140.0 / 255)
    static let accent = Color(red: 45.0 / 255, green: 138.0 / 255, blue: 106.0 / 255)
    static let accentInk = accent
    static let mint = Color(red: 225.0 / 255, green: 244.0 / 255, blue: 235.0 / 255)
    static let border = Color(red: 228.0 / 255, green: 235.0 / 255, blue: 231.0 / 255)
    static let screenPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 16
}
