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
        // One entry now and one just after midnight, so "today" rolls over without opening the app.
        let now = Date()
        let snapshot = load()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let entries = [TodayEntry(date: now, snapshot: snapshot), TodayEntry(date: midnight.addingTimeInterval(1), snapshot: snapshot)]
        let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        completion(Timeline(entries: entries, policy: .after(dayAfter)))
    }

    static var sample: WidgetSnapshot {
        let start = DayKey(date: Date()).adding(-23)
        func habit(_ title: String, _ hex: String, _ symbol: String, skip: Int) -> WidgetSnapshot.Habit {
            let done = Set((0..<23).filter { $0 % skip != 0 }.map { start.adding($0) })
            return WidgetSnapshot.Habit(id: UUID(), title: title, colorHex: hex, symbol: symbol,
                                        timeline: HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)], completed: done))
        }
        return WidgetSnapshot(habits: [habit("Rise with intention", HabitPalette.gold, "sun.max", skip: 6),
                                       habit("Train the body", HabitPalette.sage, "figure.walk", skip: 4),
                                       habit("Evening review", "#C97B5A", "pencil.line", skip: 9)], isWhiteMarble: false)
    }
}

private struct WidgetColors {
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
            if let snapshot = entry.snapshot, !snapshot.habits.isEmpty {
                if family == .systemSmall {
                    small(snapshot, colors: colors)
                } else {
                    medium(snapshot, colors: colors)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUMMA").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
                    Text("Open Summa to begin your 90 days.").font(.footnote).foregroundStyle(colors.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) { colors.background }
    }

    /// Today's habits with their status.
    private func small(_ snapshot: WidgetSnapshot, colors: WidgetColors) -> some View {
        let today = entry.today
        let due = snapshot.habits.filter { $0.timeline.status(on: today, today: today) != .unscheduled }
        let done = due.filter { $0.timeline.status(on: today, today: today) == .completed }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
                Spacer()
                Text(due.isEmpty ? "Rest" : "\(done)/\(due.count)").font(.caption2.weight(.semibold)).foregroundStyle(colors.muted)
            }
            if due.isEmpty {
                Text("Nothing is due today.").font(.footnote).foregroundStyle(colors.text)
            }
            ForEach(due.prefix(4)) { habit in
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Weekly consistency: one row per habit, Monday to Sunday.
    private func medium(_ snapshot: WidgetSnapshot, colors: WidgetColors) -> some View {
        let today = entry.today
        let week = WidgetSnapshot.week(containing: today)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("THIS WEEK").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, letter in
                    Text(letter).font(.caption2.weight(week[index] == today ? .bold : .regular))
                        .foregroundStyle(week[index] == today ? colors.text : colors.muted)
                        .frame(width: 18)
                }
            }
            ForEach(snapshot.habits.prefix(4)) { habit in
                HStack(spacing: 6) {
                    Image(systemName: habit.symbol).font(.caption2).foregroundStyle(Color(hex: habit.colorHex)).frame(width: 14)
                    Text(habit.title).font(.caption).foregroundStyle(colors.text).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(week, id: \.self) { day in
                        cell(habit.timeline.status(on: day, today: today), color: Color(hex: habit.colorHex), colors: colors)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(habit.title): \(week.filter { habit.timeline.status(on: $0, today: today) == .completed }.count) completed this week")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cell(_ status: DayStatus, color: Color, colors: WidgetColors) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        switch status {
        case .completed: shape.fill(color).frame(width: 18, height: 14)
        case .missed: shape.strokeBorder(colors.muted.opacity(0.5)).frame(width: 18, height: 14)
            .overlay(Rectangle().fill(colors.muted).frame(width: 6, height: 1.5))
        case .pending: shape.strokeBorder(color, lineWidth: 1.5).frame(width: 18, height: 14)
        case .upcoming: shape.fill(color.opacity(0.18)).frame(width: 18, height: 14)
        case .unscheduled: Circle().fill(colors.muted.opacity(0.5)).frame(width: 3, height: 3).frame(width: 18, height: 14)
        }
    }
}

struct SummaTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Summa")
        .description("Today’s habits, or your week at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SummaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaTodayWidget()
    }
}
