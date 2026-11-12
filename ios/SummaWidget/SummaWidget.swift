import WidgetKit
import SwiftUI
import SummaCore

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var today: DayKey { DayKey(date: date) }
}

struct TodayProvider: TimelineProvider {
    private func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: WidgetSnapshot.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), snapshot: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? Self.sample : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // One entry now and one just after midnight, so the day, stage, and "today" roll over without opening the app.
        let now = Date()
        let snapshot = load()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let entries = [TodayEntry(date: now, snapshot: snapshot), TodayEntry(date: midnight.addingTimeInterval(1), snapshot: snapshot)]
        let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        completion(Timeline(entries: entries, policy: .after(dayAfter)))
    }

    /// Shown only in the widget gallery.
    static var sample: WidgetSnapshot {
        let start = DayKey(date: Date()).adding(-23)
        func habit(_ title: String, _ hex: String, _ symbol: String, skip: Int) -> WidgetSnapshot.Habit {
            let done = Set((0..<23).filter { $0 % skip != 0 }.map { start.adding($0) })
            return WidgetSnapshot.Habit(id: UUID(), title: title, colorHex: hex, symbol: symbol,
                                        timeline: HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)], completed: done))
        }
        let habits = [habit("Read daily", HabitPalette.gold, "book", skip: 6), habit("Train the body", HabitPalette.sage, "figure.walk", skip: 4),
                      habit("Evening review", "#C97B5A", "pencil.line", skip: 9)]
        return WidgetSnapshot(habits: habits, isWhiteMarble: false, isPro: true, allTimelines: habits.map { $0.timeline })
    }
}

struct WidgetColors {
    let background: Color
    let text: Color
    let muted: Color
    let gold: Color

    init(white: Bool) {
        background = white ? Color(hex: "#F4F1EA") : Color(hex: "#0E0D0C")
        text = white ? Color(hex: "#1B1A17") : Color(hex: "#EEEBE4")
        muted = white ? Color(hex: "#5F5B53") : Color(hex: "#A19D95")
        gold = white ? Color(hex: "#7E5F17") : Color(hex: "#DCAF61")
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

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        let colors = WidgetColors(white: entry.snapshot?.isWhiteMarble ?? false)
        Group {
            if let snapshot = entry.snapshot, snapshot.planStart != nil {
                if snapshot.isPro == true {
                    if family == .systemSmall {
                        today(snapshot, colors: colors, limit: 3)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            today(snapshot, colors: colors, limit: 4)
                            heatmap(snapshot, colors: colors)
                        }
                    }
                } else {
                    locked(colors)
                }
            } else {
                message("Open Summa to begin your 90 days.", colors: colors)
            }
        }
        .containerBackground(for: .widget) { colors.background }
    }

    private func message(_ text: String, colors: WidgetColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUMMA").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
            Text(text).font(.footnote).foregroundStyle(colors.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Widgets are a Summa Pro feature. A widget already on the home screen cannot be removed by
    /// the app, so without Pro it shows this instead of data. Tapping opens the subscription page.
    private func locked(_ colors: WidgetColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUMMA PRO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
            Text("Widgets are part of Summa Pro.").font(.footnote.weight(.semibold)).foregroundStyle(colors.text)
            Text("Tap to see plans.").font(.caption).foregroundStyle(colors.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "summa://pro"))
    }

    /// Day, stage, days remaining, and today's habits.
    private func today(_ snapshot: WidgetSnapshot, colors: WidgetColors, limit: Int) -> some View {
        let today = entry.today
        let day = snapshot.dayNumber(today: today) ?? 1
        let remaining = snapshot.daysRemaining(today: today) ?? 0
        let stage = Stage.forDay(day)
        let finished = (snapshot.planStart.map { $0.adding(HabitTimeline.planLength - 1) < today }) ?? false
        let due = snapshot.habits.filter { $0.timeline.status(on: today, today: today) != .unscheduled }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: stage.accentHex)).frame(width: 7, height: 7)
                Text(stage.name.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(colors.text).lineLimit(1)
            }
            Text(finished ? "90 days complete" : "Day \(day) · \(remaining) left")
                .font(.caption.weight(.medium)).foregroundStyle(colors.muted).lineLimit(1)
            if due.isEmpty {
                Text(finished ? "The record stands." : "Rest day.").font(.footnote).foregroundStyle(colors.text)
            }
            ForEach(due.prefix(limit)) { habit in
                let completed = habit.timeline.status(on: today, today: today) == .completed
                HStack(spacing: 6) {
                    Image(systemName: completed ? "checkmark.square.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(Color(hex: habit.colorHex))
                    Text(habit.title).font(.caption).foregroundStyle(completed ? colors.muted : colors.text).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(habit.title), \(completed ? "completed" : "due today")")
            }
            if due.count > limit {
                Text("+\(due.count - limit) more").font(.caption2).foregroundStyle(colors.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stage.name) stage, day \(day) of 90, \(remaining) days remaining")
    }

    /// The 90 days across all habits, tinted by stage.
    private func heatmap(_ snapshot: WidgetSnapshot, colors: WidgetColors) -> some View {
        let today = entry.today
        let timelines = snapshot.allTimelines ?? snapshot.habits.map { $0.timeline }
        let start = snapshot.planStart ?? today
        let blanks = (start.weekday + 5) % 7
        let columns = Int((Double(blanks + HabitTimeline.planLength) / 7).rounded(.up))
        let progress = PlanProgress.completion(timelines: timelines, today: today)
        return VStack(alignment: .trailing, spacing: 4) {
            Canvas { context, size in
                let gap: CGFloat = 0.22
                let cell = min(size.width / (CGFloat(columns) + CGFloat(columns - 1) * gap), size.height / (7 + 6 * gap))
                let step = cell * (1 + gap)
                for index in 0..<HabitTimeline.planLength {
                    let day = start.adding(index)
                    let slot = index + blanks
                    let rect = CGRect(x: CGFloat(slot / 7) * step, y: CGFloat(slot % 7) * step, width: cell, height: cell)
                    let shape = Path(roundedRect: rect, cornerRadius: cell * 0.25)
                    let accent = Color(hex: Stage.forDay(index + 1).accentHex)
                    let info = PlanProgress.day(day, timelines: timelines, today: today)
                    switch info.status {
                    case .completed: context.fill(shape, with: .color(accent))
                    case .partial: context.fill(shape, with: .color(accent.opacity(0.5)))
                    case .missed: context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.25), with: .color(colors.muted.opacity(0.55)), lineWidth: 1)
                    case .current:
                        context.fill(shape, with: .color(accent.opacity(info.completed > 0 ? 0.5 : 0.15)))
                        context.stroke(shape, with: .color(colors.text), lineWidth: 1)
                    case .upcoming: context.fill(shape, with: .color(accent.opacity(0.16)))
                    case .rest: context.fill(Path(ellipseIn: rect.insetBy(dx: cell * 0.38, dy: cell * 0.38)), with: .color(colors.muted.opacity(0.5)))
                    }
                }
            }
            Text(progress.percent.map { "\($0)% complete" } ?? "Nothing due yet")
                .font(.caption2).foregroundStyle(colors.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.percent.map { "90-day heatmap, \($0) percent complete" } ?? "90-day heatmap")
    }
}

struct SummaTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Summa")
        .description("Today’s habits, your day and stage, and the 90-day heatmap. Requires Summa Pro.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SummaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaTodayWidget()
        SummaHabitWidget()
        SummaWeekWidget()
        SummaVictoryWidget()
    }
}
