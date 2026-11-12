import SwiftUI
import SummaCore

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(theme.onGold)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(theme.gold.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(theme.text.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(theme.surface.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var summaPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var summaSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Readable surface over the marble.
struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.divider))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Small spaced capitals used above headlines.
struct Eyebrow: View {
    @Environment(\.theme) private var theme
    let text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.medium))
            .tracking(2.4)
            .foregroundStyle(color ?? theme.muted)
    }
}

struct Hairline: View {
    @Environment(\.theme) private var theme
    var body: some View { Rectangle().fill(theme.divider).frame(height: 1) }
}

struct Wordmark: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Text("SUMMA")
            .font(SummaFont.roman(15))
            .tracking(4)
            .foregroundStyle(theme.gold)
            .accessibilityLabel("Summa")
    }
}

/// A selectable pill used for choices and weekdays.
struct Chip: View {
    @Environment(\.theme) private var theme
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
            }
            .foregroundStyle(isSelected ? theme.onGold : theme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isSelected ? theme.gold : theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : theme.divider))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wraps children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: min(bounds.width, result.sizes[index].width), height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], sizes: [CGSize], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (points, sizes, maxX, y + rowHeight)
    }
}

/// Seven toggles, Monday first.
struct WeekdayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var weekdays: [Int]
    var accent: Color?
    private let order = [2, 3, 4, 5, 6, 7, 1]
    private let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let isOn = weekdays.contains(day)
                Button {
                    Haptics.select()
                    if isOn {
                        if weekdays.count > 1 { weekdays.removeAll { $0 == day } }
                    } else {
                        weekdays = (weekdays + [day]).sorted()
                    }
                } label: {
                    Text(String(names[day - 1].prefix(1)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? theme.onGold : theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? (accent ?? theme.gold) : theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? Color.clear : theme.divider))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("weekday.\(day)")
            }
        }
    }
}

/// Sculpture inside a Roman arch. Used only on the welcome and plan reveal screens.
struct StatueArch: View {
    @Environment(\.theme) private var theme
    let imageName: String
    var alignment: Alignment = .center

    var body: some View {
        Color.black
            .overlay(alignment: alignment) {
                Image(imageName).resizable().scaledToFill()
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 140, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 140, style: .continuous))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 140, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 140, style: .continuous)
                    .strokeBorder(theme.gold.opacity(0.35), lineWidth: 1)
            )
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: theme.isDark ? 0.6 : 1), .init(color: theme.isDark ? .clear : .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }
}

extension DayKey {
    func formatted(_ style: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day()) -> String {
        date().formatted(style)
    }
}

extension Color {
    static func accent(_ hex: String) -> Color { Color(hex: HabitPalette.isValidHex(hex) ? hex : HabitPalette.gold) }
}
