import WidgetKit
import SwiftUI
import AppIntents
import SummaCore

// MARK: - Shared container

/// The snapshot the app publishes, and the queue of check-ins made from a widget button.
enum SnapshotStore {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: WidgetSnapshot.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: WidgetSnapshot.defaultsKey)
    }

    static func pending() -> [PendingCheckIn] {
        guard let data = defaults?.data(forKey: WidgetSnapshot.pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingCheckIn].self, from: data)) ?? []
    }

    static func savePending(_ queue: [PendingCheckIn]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults?.set(data, forKey: WidgetSnapshot.pendingKey)
    }

    /// Entries for now and just after midnight, so "today" rolls over without the app being opened.
    static func refreshDates(from now: Date = Date()) -> (dates: [Date], after: Date) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        return ([now, midnight.addingTimeInterval(1)], dayAfter)
    }
}

/// Shown instead of data when the account is not on Summa Pro. Tapping opens the subscription page.
struct WidgetLockedView: View {
    let colors: WidgetColors
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUMMA PRO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
            Text("Widgets are part of Summa Pro.").font(.footnote.weight(.semibold)).foregroundStyle(colors.text)
            Text("Tap to see plans.").font(.caption).foregroundStyle(colors.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "summa://pro"))
    }
}

struct WidgetMessageView: View {
    let text: String
    let colors: WidgetColors
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUMMA").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.gold)
            Text(text).font(.footnote).foregroundStyle(colors.text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - One habit, all 90 days

struct HabitEntity: AppEntity {
    let id: String
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct HabitQuery: EntityQuery {
    private func all() -> [HabitEntity] {
        (SnapshotStore.load()?.habits ?? []).map { HabitEntity(id: $0.id.uuidString, title: $0.title) }
    }

    func entities(for identifiers: [String]) async throws -> [HabitEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [HabitEntity] { all() }
    func defaultResult() async -> HabitEntity? { all().first }
}

struct SelectHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a habit"
    static var description = IntentDescription("Shows the 90-day heatmap for one habit.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

/// The check button on the wide habit widget. It marks today done (or undoes it) in the widget at
/// once and leaves a note for the app, which writes the real record the next time it is opened.
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark habit done"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Habit")
    var habitID: String

    init() {}
    init(habitID: String) { self.habitID = habitID }

    func perform() async throws -> some IntentResult {
        let today = DayKey(date: Date())
        guard let id = UUID(uuidString: habitID), let snapshot = SnapshotStore.load(), snapshot.isPro == true,
              let result = WidgetInbox.toggling(habitID: id, on: today, in: snapshot) else { return .result() }
        SnapshotStore.save(result.snapshot)
        SnapshotStore.savePending(WidgetInbox.adding(result.change, to: SnapshotStore.pending()))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let habitID: String?
    var today: DayKey { DayKey(date: date) }

    var habit: WidgetSnapshot.Habit? {
        guard let snapshot else { return nil }
        return snapshot.habits.first { $0.id.uuidString == habitID } ?? snapshot.habits.first
    }
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { HabitEntry(date: Date(), snapshot: TodayProvider.sample, habitID: nil) }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitEntry {
        HabitEntry(date: Date(), snapshot: context.isPreview ? TodayProvider.sample : SnapshotStore.load(), habitID: configuration.habit?.id)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitEntry> {
        let snapshot = SnapshotStore.load()
        let refresh = SnapshotStore.refreshDates()
        return Timeline(entries: refresh.dates.map { HabitEntry(date: $0, snapshot: snapshot, habitID: configuration.habit?.id) },
                        policy: .after(refresh.after))
    }
}

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitEntry

    var body: some View {
        let colors = WidgetColors(white: entry.snapshot?.isWhiteMarble ?? false)
        Group {
            if let snapshot = entry.snapshot, let habit = entry.habit {
                if snapshot.isPro == true {
                    content(habit, colors: colors)
                } else {
                    WidgetLockedView(colors: colors)
                }
            } else {
                WidgetMessageView(text: "Open Summa to begin your 90 days.", colors: colors)
            }
        }
        .containerBackground(for: .widget) { colors.background }
    }

    private func content(_ habit: WidgetSnapshot.Habit, colors: WidgetColors) -> some View {
        let today = entry.today
        let accent = Color(hex: habit.colorHex)
        let status = habit.timeline.status(on: today, today: today)
        let wide = family != .systemSmall
        return VStack(alignment: .leading, spacing: wide ? 8 : 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: habit.symbol).font(wide ? .body : .footnote).foregroundStyle(accent).frame(width: wide ? 22 : 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title).font(wide ? .subheadline.weight(.medium) : .footnote.weight(.medium))
                        .foregroundStyle(colors.text).lineLimit(1)
                    if wide, let detail = habit.detail, !detail.isEmpty {
                        Text(detail).font(.caption2).foregroundStyle(colors.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if wide, status == .pending || status == .completed {
                    Button(intent: ToggleHabitIntent(habitID: habit.id.uuidString)) {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(status == .completed ? colors.background : accent.opacity(0.0001))
                            .frame(width: 30, height: 30)
                            .background(status == .completed ? accent : accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(accent, lineWidth: status == .completed ? 0 : 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status == .completed ? "Undo \(habit.title) for today" : "Mark \(habit.title) done today")
                }
            }
            HabitGrid(timeline: habit.timeline, today: today, accent: accent, colors: colors, rows: wide ? 5 : 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(habit.title), 90-day heatmap. Today: \(status.label).")
    }
}

/// All 90 days of one habit in its own color. The small widget keeps weeks in columns (Monday at
/// the top); the wide one runs the days in order, five to a column, so the grid fills its width.
struct HabitGrid: View {
    let timeline: HabitTimeline
    let today: DayKey
    let accent: Color
    let colors: WidgetColors
    let rows: Int

    var body: some View {
        let blanks = rows == 7 ? (timeline.planStart.weekday + 5) % 7 : 0
        let columns = Int((Double(blanks + timeline.length) / Double(rows)).rounded(.up))
        Canvas { context, size in
            let gap: CGFloat = 0.24
            let cell = min(size.width / (CGFloat(columns) + CGFloat(columns - 1) * gap), size.height / (CGFloat(rows) + CGFloat(rows - 1) * gap))
            let step = cell * (1 + gap)
            let offsetX = (size.width - (CGFloat(columns) * step - cell * gap)) / 2
            for index in 0..<timeline.length {
                let day = timeline.planStart.adding(index)
                let slot = index + blanks
                let rect = CGRect(x: offsetX + CGFloat(slot / rows) * step, y: CGFloat(slot % rows) * step, width: cell, height: cell)
                let shape = Path(roundedRect: rect, cornerRadius: cell * 0.26, style: .continuous)
                switch timeline.status(on: day, today: today) {
                case .completed: context.fill(shape, with: .color(accent))
                case .missed: context.fill(shape, with: .color(accent.opacity(0.28)))
                case .pending:
                    context.fill(shape, with: .color(accent.opacity(0.16)))
                    context.stroke(Path(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), cornerRadius: cell * 0.26, style: .continuous), with: .color(colors.text), lineWidth: 1.2)
                case .upcoming: context.fill(shape, with: .color(accent.opacity(0.12)))
                case .unscheduled: context.fill(shape, with: .color(colors.muted.opacity(0.10)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct SummaHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshot.habitWidgetKind, intent: SelectHabitIntent.self, provider: HabitProvider()) { entry in
            HabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Habit heatmap")
        .description("All 90 days of one habit. The wide size adds a button to mark today done. Requires Summa Pro.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - This week, every habit

struct WeekWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        let colors = WidgetColors(white: entry.snapshot?.isWhiteMarble ?? false)
        Group {
            if let snapshot = entry.snapshot, snapshot.planStart != nil {
                if snapshot.isPro == true { grid(snapshot, colors: colors) } else { WidgetLockedView(colors: colors) }
            } else {
                WidgetMessageView(text: "Open Summa to begin your 90 days.", colors: colors)
            }
        }
        .containerBackground(for: .widget) { colors.background }
    }

    private func grid(_ snapshot: WidgetSnapshot, colors: WidgetColors) -> some View {
        let today = entry.today
        let week = WidgetSnapshot.week(containing: today)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let habits = Array(snapshot.habits.prefix(4))
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 22, height: 1)
                ForEach(0..<7, id: \.self) { index in
                    Text(letters[index]).font(.caption2.weight(week[index] == today ? .bold : .regular))
                        .foregroundStyle(week[index] == today ? colors.text : colors.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(habits) { habit in
                let accent = Color(hex: habit.colorHex)
                HStack(spacing: 6) {
                    Image(systemName: habit.symbol).font(.caption).foregroundStyle(colors.muted).frame(width: 22)
                    ForEach(0..<7, id: \.self) { index in
                        let status = habit.timeline.contains(week[index]) ? habit.timeline.status(on: week[index], today: today) : .unscheduled
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(fill(status, accent: accent, colors: colors))
                            .overlay {
                                if status == .pending {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(accent, lineWidth: 1.2)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(habit.title): \(week.filter { habit.timeline.contains($0) && habit.timeline.status(on: $0, today: today) == .completed }.count) days done this week")
            }
            if habits.isEmpty { Text("No active habits.").font(.footnote).foregroundStyle(colors.muted) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fill(_ status: DayStatus, accent: Color, colors: WidgetColors) -> Color {
        switch status {
        case .completed: return accent
        case .missed: return accent.opacity(0.26)
        case .pending: return accent.opacity(0.14)
        case .upcoming: return accent.opacity(0.10)
        case .unscheduled: return colors.muted.opacity(0.08)
        }
    }
}

struct SummaWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.weekWidgetKind, provider: TodayProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("This week")
        .description("Monday to Sunday for each habit, in its own color. Requires Summa Pro.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Log a victory with Summa

struct VictoryWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        let colors = WidgetColors(white: entry.snapshot?.isWhiteMarble ?? false)
        Group {
            if let snapshot = entry.snapshot, snapshot.planStart != nil {
                if snapshot.isPro == true { prompt(colors) } else { WidgetLockedView(colors: colors) }
            } else {
                WidgetMessageView(text: "Open Summa to begin your 90 days.", colors: colors)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                colors.background
                RadialGradient(colors: [colors.gold.opacity(0.22), .clear], center: .top, startRadius: 2, endRadius: 150)
            }
        }
    }

    private func prompt(_ colors: WidgetColors) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                Image(systemName: "mic.fill").font(.title3)
                    .frame(width: 44, height: 44)
                    .background(colors.gold.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(colors.gold, lineWidth: 1.2))
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(colors.gold)
            Text("LOG A VICTORY").font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(colors.gold)
            Text("Tell Summa").font(.footnote).foregroundStyle(colors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetSnapshot.victoryURL))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log a victory. Opens a conversation with Summa.")
    }
}

struct SummaVictoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.victoryWidgetKind, provider: TodayProvider()) { entry in
            VictoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Log a victory")
        .description("Opens Talk to Summa so you can record a win for Your Colosseum. Requires Summa Pro.")
        .supportedFamilies([.systemSmall])
    }
}
