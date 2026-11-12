import SwiftUI
import SummaCore

/// How one day is drawn. Each status has its own shape as well as its own tone,
/// so the record reads without relying on color alone.
enum DayCellRenderer {
    static func draw(_ status: DayStatus, in rect: CGRect, context: inout GraphicsContext, accent: Color, theme: Theme,
                     isToday: Bool, isSelected: Bool) {
        let radius = rect.width * 0.24
        let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        switch status {
        case .completed:
            context.fill(shape, with: .color(accent))
        case .missed:
            context.fill(shape, with: .color(theme.muted.opacity(0.10)))
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous),
                           with: .color(theme.muted.opacity(0.45)), lineWidth: 1)
            var dash = Path()
            dash.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY))
            dash.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.midY))
            context.stroke(dash, with: .color(theme.muted.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, rect.width * 0.1), lineCap: .round))
        case .pending:
            context.fill(shape, with: .color(accent.opacity(0.16)))
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius, style: .continuous),
                           with: .color(accent), lineWidth: 1.5)
        case .upcoming:
            context.fill(shape, with: .color(accent.opacity(theme.isDark ? 0.13 : 0.2)))
        case .unscheduled:
            let dot = rect.insetBy(dx: rect.width * 0.4, dy: rect.height * 0.4)
            context.fill(Path(ellipseIn: dot), with: .color(theme.muted.opacity(0.45)))
        }
        if isToday {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2, style: .continuous),
                           with: .color(theme.text.opacity(0.85)), lineWidth: 1)
        }
        if isSelected {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: radius + 2.5, style: .continuous),
                           with: .color(theme.gold), lineWidth: 2)
        }
    }
}

/// A GitHub-style grid of the plan's 90 days: one column per week, Monday at the top.
struct HeatmapGrid: View {
    @Environment(\.theme) private var theme
    let timeline: HabitTimeline
    let today: DayKey
    let accent: Color
    var selection: Binding<DayKey?>?

    private var leadingBlanks: Int { (timeline.planStart.weekday + 5) % 7 }
    private var columns: Int { Int((Double(leadingBlanks + timeline.length) / 7).rounded(.up)) }
    private let gapRatio: CGFloat = 0.2

    var body: some View {
        let aspect = (CGFloat(columns) + CGFloat(columns - 1) * gapRatio) / (7 + 6 * gapRatio)
        Canvas { context, size in
            let cell = size.width / (CGFloat(columns) + CGFloat(columns - 1) * gapRatio)
            let step = cell * (1 + gapRatio)
            for index in 0..<timeline.length {
                let day = timeline.planStart.adding(index)
                let slot = index + leadingBlanks
                let rect = CGRect(x: CGFloat(slot / 7) * step, y: CGFloat(slot % 7) * step, width: cell, height: cell)
                DayCellRenderer.draw(timeline.status(on: day, today: today), in: rect, context: &context, accent: accent,
                                     theme: theme, isToday: day == today, isSelected: selection?.wrappedValue == day)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .padding(3)
        .contentShape(Rectangle())
        .overlay {
            if let selection {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let width = proxy.size.width - 6
                            let cell = width / (CGFloat(columns) + CGFloat(columns - 1) * gapRatio)
                            let step = cell * (1 + gapRatio)
                            let column = Int((value.location.x - 3) / step)
                            let row = Int((value.location.y - 3) / step)
                            guard column >= 0, column < columns, row >= 0, row < 7 else { return }
                            let index = column * 7 + row - leadingBlanks
                            guard index >= 0, index < timeline.length else { return }
                            let day = timeline.planStart.adding(index)
                            if selection.wrappedValue != day {
                                selection.wrappedValue = day
                                Haptics.select()
                            }
                        })
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("90-day heatmap")
        .accessibilityValue(summary)
        .modifier(AdjustableDay(selection: selection, timeline: timeline, today: today))
    }

    /// Spoken summary of the record so far.
    private var summary: String {
        var counts: [DayStatus: Int] = [:]
        for day in timeline.days where day <= today { counts[timeline.status(on: day, today: today), default: 0] += 1 }
        let dayNumber = timeline.dayNumber(today: today) ?? 0
        var parts = ["Day \(dayNumber) of \(timeline.length)", "\(counts[.completed, default: 0]) completed", "\(counts[.missed, default: 0]) missed",
                     "\(counts[.unscheduled, default: 0]) rest days"]
        if timeline.contains(today) { parts.append("Today: \(timeline.status(on: today, today: today).label)") }
        if let selected = selection?.wrappedValue {
            parts.insert("Selected \(selected.formatted()): \(timeline.status(on: selected, today: today).label)", at: 0)
        }
        return parts.joined(separator: ", ")
    }
}

/// Lets VoiceOver users step through individual dates with swipe up and down.
private struct AdjustableDay: ViewModifier {
    let selection: Binding<DayKey?>?
    let timeline: HabitTimeline
    let today: DayKey

    func body(content: Content) -> some View {
        if let selection {
            content
                .accessibilityHint("Swipe up or down to inspect individual days")
                .accessibilityAdjustableAction { direction in
                    let current = selection.wrappedValue ?? min(max(today, timeline.planStart), timeline.planEnd)
                    let next = current.adding(direction == .increment ? 1 : -1)
                    if timeline.contains(next) { selection.wrappedValue = next }
                }
        } else {
            content
        }
    }
}

/// A single day drawn the same way as in the grid. Used by the legend and the calendar.
struct DayCell: View {
    @Environment(\.theme) private var theme
    let status: DayStatus
    let accent: Color
    var isToday = false
    var isSelected = false

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) - 6
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            DayCellRenderer.draw(status, in: rect, context: &context, accent: accent, theme: theme, isToday: isToday, isSelected: isSelected)
        }
    }
}

struct HeatmapLegend: View {
    @Environment(\.theme) private var theme
    let accent: Color

    var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(DayStatus.allCases, id: \.self) { status in
                HStack(spacing: 6) {
                    DayCell(status: status, accent: accent).frame(width: 20, height: 20)
                    Text(status.label).font(.caption).foregroundStyle(theme.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: filled is completed, a dash is missed, an outline is due today, a faint square is upcoming, a dot is a rest day.")
    }
}
