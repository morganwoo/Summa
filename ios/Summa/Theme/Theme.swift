import SwiftUI
import UIKit

enum ThemeChoice: String, CaseIterable, Identifiable {
    case black, white
    static let storageKey = "summa.theme"
    var id: String { rawValue }
    var name: String { self == .black ? "Black Marble" : "White Marble" }
    var theme: Theme { self == .black ? .blackMarble : .whiteMarble }
}

/// Colors for one marble theme. Text colors meet WCAG AA on `surface` and `background`.
struct Theme: Equatable {
    let isDark: Bool
    let background: Color
    let backgroundEdge: Color
    let surface: Color
    let surfaceRaised: Color
    let text: Color
    let muted: Color
    /// Antique gold for accents, rules, and primary actions.
    let gold: Color
    /// Text drawn on top of gold.
    let onGold: Color
    let divider: Color
    let vein: Color

    static let blackMarble = Theme(
        isDark: true,
        background: Color(hex: "#040404"), backgroundEdge: Color(hex: "#12110F"),
        surface: Color(hex: "#0E0D0C").opacity(0.92), surfaceRaised: Color(hex: "#191816"),
        text: Color(hex: "#EEEBE4"), muted: Color(hex: "#A19D95"),
        gold: Color(hex: "#DCAF61"), onGold: Color(hex: "#14110A"),
        divider: Color(hex: "#EEEBE4").opacity(0.14), vein: Color(hex: "#EEEBE4"))

    static let whiteMarble = Theme(
        isDark: false,
        background: Color(hex: "#F4F1EA"), backgroundEdge: Color(hex: "#E4DFD4"),
        surface: Color(hex: "#FFFDF8").opacity(0.92), surfaceRaised: Color(hex: "#ECE7DC"),
        text: Color(hex: "#1B1A17"), muted: Color(hex: "#5F5B53"),
        gold: Color(hex: "#7E5F17"), onGold: Color(hex: "#FFFDF8"),
        divider: Color(hex: "#1B1A17").opacity(0.14), vein: Color(hex: "#6E6A61"))
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.blackMarble
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}

/// Editorial serif for headlines, Roman capitals for the wordmark, system type for controls and data.
enum SummaFont {
    private static let hasSerif = UIFont(name: "SummaCormorant-Regular", size: 12) != nil
    private static let hasItalic = UIFont(name: "SummaCormorant-Italic", size: 12) != nil
    private static let hasRoman = UIFont(name: "SummaCinzel-Regular", size: 12) != nil

    /// Display serif that scales with Dynamic Type.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        hasSerif ? .custom("SummaCormorant-Regular", size: size, relativeTo: style)
                 : .system(size: size * 0.86, weight: .regular, design: .serif)
    }

    static func serifItalic(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        hasItalic ? .custom("SummaCormorant-Italic", size: size, relativeTo: style)
                  : .system(size: size * 0.86, weight: .regular, design: .serif).italic()
    }

    static func roman(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        hasRoman ? .custom("SummaCinzel-Regular", size: size, relativeTo: style)
                 : .system(size: size, weight: .medium, design: .serif)
    }
}

@MainActor
enum Haptics {
    static func commit() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func complete() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9) }
    static func undo() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
