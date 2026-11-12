import SwiftUI
import SwiftData
import SummaCore

/// Streaks first, then the same record three ways: heatmap, month calendar, completion.
struct ProgressScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    @Binding var selectedHabitID: UUID?

    @State private var selectedDay: DayKey? = nil
    @State private var monthAnchor: DayKey? = nil
    @State private var period = 0
    @State private var showRules = false

    private var habits: [Habit] { plan.activeHabits + plan.archivedHabits }
    private var habit: Habit? { habits.first { $0.id == selectedHabitID } ?? habits.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Your progress")
                    Text("Discipline, made visible.")
                        .font(SummaFont.serif(36, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                }
                if let habit {
                    selector(current: habit)
                    content(for: habit)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing to show yet.").font(SummaFont.serif(24, relativeTo: .title3))
                        Text("Add a habit to your plan and its record will appear here.").font(.subheadline).foregroundStyle(theme.muted)
                    }
                    .card()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onChange(of: selectedHabitID) { _, _ in selectedDay = nil }
    }

    private func selector(current: Habit) -> some View {
        Menu {
            ForEach(habits) { item in
                Button {
                    selectedHabitID = item.id
                } label: {
                    Label(item.archivedDay == nil ? item.title : "\(item.title) (archived)", systemImage: item.symbol)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: current.symbol)
                    .foregroundStyle(Color.accent(current.colorHex))
                    .frame(width: 36, height: 36)
                    .background(Color.accent(current.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.headline).foregroundStyle(theme.text)
                    Text(OnboardingFlow.describe(weekdays: current.currentWeekdays)).font(.footnote).foregroundStyle(theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(theme.muted)
            }
            .card(padding: 14)
        }
        .accessibilityLabel("Habit: \(current.title)")
        .accessibilityHint("Chooses which habit to show")
        .accessibilityIdentifier("progress.selector")
    }

    @ViewBuilder
    private func content(for habit: Habit) -> some View {
        let today = clock.today
        let timeline = habit.timeline(planStart: plan.start)
        let accent = Color.accent(habit.colorHex)
        let overall = HabitMetrics.compute(timeline, today: today)
        let anchor = monthAnchor ?? min(max(today, plan.start), plan.end)
        let month = MonthCalendar.range(containing: anchor)

        // Streaks
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Streak", color: accent)
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                stat("\(overall.currentStreak)", "current", id: "progress.currentStreak")
                stat("\(overall.longestStreak)", "longest", id: "progress.longestStreak")
            }
            Text(streakNote(overall))
                .font(.footnote).foregroundStyle(theme.muted)
        }
        .card()

        // Heatmap
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("The 90 days")
            HeatmapGrid(timeline: timeline, today: today, accent: accent, selection: $selectedDay)
            HStack {
                Text(plan.start.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text(plan.end.formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.caption).foregroundStyle(theme.muted)
            .accessibilityHidden(true)
            inspector(timeline: timeline, today: today)
            HeatmapLegend(accent: accent)
        }
        .card()

        // Calendar
        VStack(alignment: .leading, spacing: 12) {
            MonthCalendar(anchor: anchor, timeline: timeline, today: today, accent: accent, selection: $selectedDay,
                          canGoBack: month.lowerBound > plan.start, canGoForward: month.upperBound < plan.end,
                          onStep: { delta in
                              monthAnchor = delta > 0 ? month.upperBound.adding(1) : month.lowerBound.adding(-1)
                          })
        }
        .card()

        // Completion
        let scoped = period == 0 ? overall : HabitMetrics.compute(timeline, today: today, range: month)
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Completion")
            Picker("Period", selection: $period) {
                Text("Plan so far").tag(0)
                Text(anchor.formatted(.dateTime.month(.wide))).tag(1)
            }
            .pickerStyle(.segmented)
            if let percent = scoped.completionPercent, let range = scoped.measuredRange {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(percent)%")
                        .font(SummaFont.serif(56, relativeTo: .largeTitle))
                        .foregroundStyle(accent)
                        .accessibilityIdentifier("progress.completion")
                    Text("\(scoped.completedCount) of \(scoped.scheduledCount) scheduled days")
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.16))
                        Capsule().fill(accent).frame(width: max(4, proxy.size.width * CGFloat(scoped.completion ?? 0)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text("\(range.lowerBound.formatted(.dateTime.month(.abbreviated).day())) – \(range.upperBound.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.footnote).foregroundStyle(theme.muted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing was due in this period.").font(.subheadline.weight(.semibold))
                    Text(emptyNote(timeline: timeline, today: today)).font(.footnote).foregroundStyle(theme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()

        rules
    }

    private func stat(_ value: String, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(SummaFont.serif(64, relativeTo: .largeTitle))
                .accessibilityIdentifier(id)
            Text(label).font(.footnote).foregroundStyle(theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) streak: \(value) scheduled \(value == "1" ? "day" : "days") in a row")
        .accessibilityIdentifier(id)
    }

    private func streakNote(_ metrics: HabitMetrics) -> String {
        switch metrics.todayStatus {
        case .pending: return "Today is still open. It joins the streak when you check in, and cannot break it before the day ends."
        case .completed: return "Today is counted."
        default: return "Counted in scheduled days. Rest days keep the streak intact."
        }
    }

    private func emptyNote(timeline: HabitTimeline, today: DayKey) -> String {
        if let next = timeline.nextScheduledDay(after: today.adding(-1)) {
            return "The next scheduled day is \(next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))."
        }
        return "There are no scheduled days left in this plan."
    }

    @ViewBuilder
    private func inspector(timeline: HabitTimeline, today: DayKey) -> some View {
        let day = selectedDay ?? (timeline.contains(today) ? today : nil)
        if let day {
            let status = timeline.status(on: day, today: today)
            HStack(spacing: 10) {
                DayCell(status: status, accent: theme.muted, isToday: day == today).frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline.weight(.semibold))
                    Text("Day \(timeline.planStart.days(until: day) + 1) · \(status.label)").font(.footnote).foregroundStyle(theme.muted)
                }
                Spacer()
                if selectedDay != nil {
                    Button("Today") { selectedDay = nil }
                        .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                }
            }
            .padding(12)
            .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            Text("Touch a square or a date to inspect that day.").font(.footnote).foregroundStyle(theme.muted)
        }
    }

    private var rules: some View {
        DisclosureGroup(isExpanded: $showRules) {
            VStack(alignment: .leading, spacing: 10) {
                rule("A streak counts scheduled days completed in a row. Rest days never break it.")
                rule("Today stays open until the day ends. An unfinished today does not break your streak.")
                rule("Completion is completed scheduled days divided by all scheduled days from the start of the period through today, or the end of the period if that came first. Today counts as scheduled.")
                rule("A missed day stays in the record. The next scheduled day is always a fresh occurrence.")
                rule("Changing a schedule applies from the day you change it. Earlier days keep their original schedule.")
            }
            .padding(.top, 10)
        } label: {
            Text("How this is counted").font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
        }
        .tint(theme.gold)
        .card()
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(theme.gold).frame(width: 4, height: 4).offset(y: -3)
            Text(text).font(.footnote).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One month in the habit's accent color. Every date is a button, so individual
/// days can be inspected by touch or with VoiceOver.
struct MonthCalendar: View {
    @Environment(\.theme) private var theme
    let anchor: DayKey
    let timeline: HabitTimeline
    let today: DayKey
    let accent: Color
    @Binding var selection: DayKey?
    let canGoBack: Bool
    let canGoForward: Bool
    let onStep: (Int) -> Void

    /// First and last day of the month containing `day`.
    static func range(containing day: DayKey) -> ClosedRange<DayKey> {
        let c = day.components
        let first = DayKey(year: c.year, month: c.month, day: 1)
        let nextMonth = c.month == 12 ? DayKey(year: c.year + 1, month: 1, day: 1) : DayKey(year: c.year, month: c.month + 1, day: 1)
        return first...nextMonth.adding(-1)
    }

    private var slots: [DayKey?] {
        let month = Self.range(containing: anchor)
        let blanks = (month.lowerBound.weekday + 5) % 7
        let count = month.lowerBound.days(until: month.upperBound) + 1
        return Array(repeating: nil, count: blanks) + (0..<count).map { month.lowerBound.adding($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(anchor.formatted(.dateTime.month(.wide).year()))
                    .font(SummaFont.serif(24, relativeTo: .title3))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                stepButton("chevron.left", label: "Previous month", enabled: canGoBack) { onStep(-1) }
                stepButton("chevron.right", label: "Next month", enabled: canGoForward) { onStep(1) }
            }
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption2.weight(.semibold)).foregroundStyle(theme.muted).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    if let day = slot {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? theme.text : theme.muted.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: DayKey) -> some View {
        let inPlan = timeline.contains(day)
        let status = timeline.status(on: day, today: today)
        return Button {
            guard inPlan else { return }
            selection = day
            Haptics.select()
        } label: {
            ZStack {
                if inPlan {
                    DayCell(status: status == .unscheduled ? .upcoming : status, accent: status == .unscheduled ? Color.clear : accent,
                            isToday: day == today, isSelected: selection == day)
                }
                Text("\(day.components.day)")
                    .font(.footnote.weight(status == .completed ? .bold : .regular))
                    .foregroundStyle(textColor(status, inPlan: inPlan))
                    .offset(y: status == .missed ? -5 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inPlan)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(inPlan ? status.label : "outside the plan")")
        .accessibilityAddTraits(selection == day ? .isSelected : [])
    }

    private func textColor(_ status: DayStatus, inPlan: Bool) -> Color {
        guard inPlan else { return theme.muted.opacity(0.35) }
        switch status {
        case .completed: return Color.black.opacity(0.85)
        case .unscheduled: return theme.muted.opacity(0.7)
        default: return theme.text
        }
    }
}
