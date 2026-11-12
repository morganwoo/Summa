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

extension DayCellRenderer {
    /// One day across all habits. A partly completed day is filled from the bottom in proportion
    /// to what was done, so it reads differently from both a full day and a missed one.
    static func draw(_ day: PlanDay, in rect: CGRect, context: inout GraphicsContext, accent: Color, theme: Theme, isToday: Bool) {
        let radius = rect.width * 0.24
        func partialFill() {
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            context.fill(shape, with: .color(accent.opacity(0.18)))
            let portion = CGFloat(min(0.8, max(0.3, day.fraction)))
            let filled = CGRect(x: rect.minX, y: rect.maxY - rect.height * portion, width: rect.width, height: rect.height * portion)
            context.fill(Path(roundedRect: filled, cornerRadius: radius * 0.6, style: .continuous), with: .color(accent))
        }
        switch day.status {
        case .completed: draw(.completed, in: rect, context: &context, accent: accent, theme: theme, isToday: isToday, isSelected: false)
        case .missed: draw(.missed, in: rect, context: &context, accent: accent, theme: theme, isToday: isToday, isSelected: false)
        case .upcoming: draw(.upcoming, in: rect, context: &context, accent: accent, theme: theme, isToday: isToday, isSelected: false)
        case .rest: draw(.unscheduled, in: rect, context: &context, accent: accent, theme: theme, isToday: isToday, isSelected: false)
        case .partial:
            partialFill()
        case .current:
            if day.completed > 0 { partialFill() } else { context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(accent.opacity(0.16))) }
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius, style: .continuous), with: .color(accent), lineWidth: 1.5)
        }
        if isToday, day.status == .partial || day.status == .current {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2, style: .continuous),
                           with: .color(theme.text.opacity(0.85)), lineWidth: 1)
        }
    }
}

extension DayCellRenderer {
    /// A brighter gold than any stage color, so the mark for a reflected day still reads on a gold Transformation day.
    static let reflectionGold = Color(hex: "#F6D98A")

    /// A still, soft halo with a fine ring. Drawn once; nothing here animates.
    static func drawReflectionGlow(around rect: CGRect, context: inout GraphicsContext, bright: Bool) {
        let radius = rect.width * 0.24
        let spread = rect.width * 0.16
        let halo = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread), cornerRadius: radius + spread, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(1.5, rect.width * 0.14)))
            layer.fill(halo, with: .color(reflectionGold.opacity(bright ? 0.95 : 0.6)))
        }
    }

    static func drawReflectionRing(around rect: CGRect, context: inout GraphicsContext, bright: Bool) {
        let radius = rect.width * 0.24
        context.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: radius + 1.5, style: .continuous),
                       with: .color(reflectionGold.opacity(bright ? 1 : 0.9)), lineWidth: bright ? 1.6 : 1.1)
    }
}

/// The whole program in one grid: every habit combined, each day tinted by its stage.
///
/// Days with a saved reflection carry a still gold halo. When `selection` is given, tapping a day
/// lifts its tile slightly, like a pressed and embossed tile, and it stays lifted while that day is open.
struct OverallHeatmap: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let timelines: [HabitTimeline]
    let planStart: DayKey
    let today: DayKey
    var reflectionDays: Set<DayKey> = []
    var selection: Binding<DayKey?>? = nil

    /// The last tile that was lifted. It stays in place while it settles back down.
    @State private var raised: DayKey? = nil

    private var leadingBlanks: Int { (planStart.weekday + 5) % 7 }
    private var columns: Int { Int((Double(leadingBlanks + HabitTimeline.planLength) / 7).rounded(.up)) }
    private let gap: CGFloat = 0.2
    /// Room around the grid for halos and for the lifted tile.
    private let margin: CGFloat = 5

    /// `width` is the width of the grid itself; the canvas is drawn `margin` wider on every side.
    private func cellSide(width: CGFloat) -> CGFloat { width / (CGFloat(columns) + CGFloat(columns - 1) * gap) }

    private func rect(index: Int, width: CGFloat) -> CGRect {
        let cell = cellSide(width: width)
        let step = cell * (1 + gap)
        let slot = index + leadingBlanks
        return CGRect(x: CGFloat(slot / 7) * step, y: CGFloat(slot % 7) * step, width: cell, height: cell)
    }

    private func dayIndex(at point: CGPoint, width: CGFloat) -> Int? {
        let step = cellSide(width: width) * (1 + gap)
        let column = Int(floor(point.x / step)), row = Int(floor(point.y / step))
        guard column >= 0, column < columns, row >= 0, row < 7 else { return nil }
        let index = column * 7 + row - leadingBlanks
        return (0..<HabitTimeline.planLength).contains(index) ? index : nil
    }

    var body: some View {
        let grid = (CGFloat(columns) + CGFloat(columns - 1) * gap) / (7 + 6 * gap)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for index in 0..<HabitTimeline.planLength {
                        let day = planStart.adding(index)
                        let cellRect = rect(index: index, width: size.width - margin * 2).offsetBy(dx: margin, dy: margin)
                        let reflected = reflectionDays.contains(day)
                        if reflected { DayCellRenderer.drawReflectionGlow(around: cellRect, context: &context, bright: false) }
                        DayCellRenderer.draw(PlanProgress.day(day, timelines: timelines, today: today), in: cellRect, context: &context,
                                             accent: Stage.forDay(index + 1).color, theme: theme, isToday: day == today)
                        if reflected { DayCellRenderer.drawReflectionRing(around: cellRect, context: &context, bright: false) }
                    }
                }
                .padding(-margin)
                if let raised, selection != nil {
                    let index = planStart.days(until: raised)
                    let cellRect = rect(index: index, width: width)
                    RaisedTile(day: PlanProgress.day(raised, timelines: timelines, today: today), accent: Stage.forDay(index + 1).color,
                               isToday: raised == today, reflected: reflectionDays.contains(raised),
                               isSelected: selection?.wrappedValue == raised, side: cellRect.width)
                        .position(x: cellRect.midX, y: cellRect.midY)
                        .id(raised)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                guard let selection, let index = dayIndex(at: value.location, width: width) else { return }
                let day = planStart.adding(index)
                Haptics.select()
                selection.wrappedValue = selection.wrappedValue == day ? nil : day // one day at a time
            }, including: selection == nil ? .subviews : .all)
        }
        .aspectRatio(grid, contentMode: .fit)
        .padding(margin)
        .onChange(of: selection?.wrappedValue) { _, selected in
            if let selected { raised = selected }
        }
        .accessibilityElement()
        .accessibilityLabel("90-day heatmap for all habits")
        .accessibilityValue(summary)
        .accessibilityHint(selection == nil ? "" : "Swipe up or down to choose a day, then double tap to open it")
        .accessibilityAdjustableAction { direction in
            guard selection != nil else { return }
            let current = raised ?? min(max(today, planStart), planStart.adding(HabitTimeline.planLength - 1))
            let next = current.adding(direction == .increment ? 1 : -1)
            if (0..<HabitTimeline.planLength).contains(planStart.days(until: next)) { raised = next }
        }
        .accessibilityAction {
            guard let selection else { return }
            selection.wrappedValue = raised ?? min(max(today, planStart), planStart.adding(HabitTimeline.planLength - 1))
        }
        .accessibilityIdentifier("overall.heatmap")
    }

    private var summary: String {
        var counts: [PlanDay.Status: Int] = [:]
        for index in 0..<HabitTimeline.planLength {
            let day = planStart.adding(index)
            guard day <= today else { break }
            counts[PlanProgress.day(day, timelines: timelines, today: today).status, default: 0] += 1
        }
        let todayPart = PlanProgress.day(today, timelines: timelines, today: today)
        var parts = ["\(counts[.completed, default: 0]) days fully done", "\(counts[.partial, default: 0]) partly done",
                     "\(counts[.missed, default: 0]) missed", "\(counts[.rest, default: 0]) rest days"]
        if todayPart.scheduled > 0 { parts.append("Today: \(todayPart.completed) of \(todayPart.scheduled) done") }
        if !reflectionDays.isEmpty { parts.append("\(reflectionDays.count) days with a reflection") }
        if let raised, selection != nil {
            let number = planStart.days(until: raised) + 1
            let status = PlanProgress.day(raised, timelines: timelines, today: today).status.label
            parts.insert("Day \(number), \(raised.formatted()): \(status)\(reflectionDays.contains(raised) ? ", has a reflection" : "")", at: 0)
        }
        return parts.joined(separator: ", ")
    }
}

/// The selected day, drawn on top of the grid and lifted to about 1.10 times its size with a soft shadow.
/// It rises when chosen and settles when the day is closed. With Reduce Motion it is outlined in place instead.
private struct RaisedTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: PlanDay
    let accent: Color
    let isToday: Bool
    let reflected: Bool
    let isSelected: Bool
    let side: CGFloat

    @State private var lifted = false
    private let pad: CGFloat = 6
    private var spring: Animation { .spring(response: 0.24, dampingFraction: 0.72) }

    var body: some View {
        Canvas { context, size in
            let cellRect = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2)
            // Cover the tile underneath so the lifted copy is the only one seen.
            context.fill(Path(roundedRect: cellRect, cornerRadius: cellRect.width * 0.24, style: .continuous), with: .color(theme.surface))
            if reflected { DayCellRenderer.drawReflectionGlow(around: cellRect, context: &context, bright: lifted) }
            DayCellRenderer.draw(day, in: cellRect, context: &context, accent: accent, theme: theme, isToday: isToday)
            if reflected { DayCellRenderer.drawReflectionRing(around: cellRect, context: &context, bright: lifted) }
            if lifted && !reflected {
                context.stroke(Path(roundedRect: cellRect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: cellRect.width * 0.24 + 1.5, style: .continuous),
                               with: .color(theme.gold), lineWidth: 1.4)
            }
        }
        .frame(width: side + pad * 2, height: side + pad * 2)
        .scaleEffect(lifted && !reduceMotion ? 1.10 : 1)
        .shadow(color: .black.opacity(lifted ? (theme.isDark ? 0.55 : 0.28) : 0), radius: lifted ? 4 : 0, x: 0, y: lifted ? 2.5 : 0)
        .opacity(lifted || isSelected ? 1 : 0)
        .onAppear { set(isSelected) }
        .onChange(of: isSelected) { _, selected in set(selected) }
    }

    private func set(_ selected: Bool) {
        if reduceMotion { lifted = selected } else { withAnimation(spring) { lifted = selected } }
    }
}

struct OverallLegend: View {
    @Environment(\.theme) private var theme

    private let samples: [PlanDay] = [
        PlanDay(status: .completed, completed: 2, scheduled: 2), PlanDay(status: .partial, completed: 1, scheduled: 2),
        PlanDay(status: .missed, completed: 0, scheduled: 2), PlanDay(status: .current, completed: 0, scheduled: 2),
        PlanDay(status: .upcoming, completed: 0, scheduled: 2), PlanDay(status: .rest, completed: 0, scheduled: 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 12) {
                ForEach(samples, id: \.status) { sample in
                    HStack(spacing: 6) {
                        Canvas { context, size in
                            let side = min(size.width, size.height) - 6
                            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
                            DayCellRenderer.draw(sample, in: rect, context: &context, accent: theme.gold, theme: theme, isToday: false)
                        }
                        .frame(width: 20, height: 20)
                        Text(sample.status.label).font(.caption).foregroundStyle(theme.muted)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(Stage.allCases, id: \.self) { stage in
                    HStack(spacing: 5) {
                        Circle().fill(stage.color).frame(width: 8, height: 8)
                        Text(stage.name).font(.caption).foregroundStyle(theme.muted)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: filled is all done, half filled is partly done, a dash is missed, an outline is today, faint is upcoming, a dot is a rest day. Green is Foundation, red is Momentum, gold is Transformation.")
    }
}
