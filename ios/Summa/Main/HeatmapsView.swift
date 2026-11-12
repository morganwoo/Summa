import SwiftUI
import SwiftData
import SummaCore

/// The daily-use screen: every active habit with its 90-day record and a one-tap check-in.
struct HeatmapsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    let openProgress: (Habit) -> Void
    let openPlan: () -> Void
    let openJourney: (JourneySheet) -> Void

    @State private var undoTarget: Habit? = nil
    @State private var undoToken = 0

    private let milestones: [Int: String] = [
        7: "One week. What surprised you?",
        14: "Two weeks. What is getting in the way, and what is not?",
        21: "Your footing is found. What has become easier?",
        66: "Rhythm. What would you keep without being asked?",
        90: "Day ninety. This is yours now.",
    ]

    var body: some View {
        let today = clock.today
        let habits = plan.activeHabits
        let dayNumber = plan.dayNumber(today: today)
        let timelines = plan.timelines
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(today: today, dayNumber: dayNumber, timelines: timelines)
                if !habits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("All habits · 90 days")
                        OverallHeatmap(timelines: timelines, planStart: plan.start, today: today)
                        OverallLegend()
                    }
                    .card()
                }
                if let week = ReportMemory.unseenWeek(for: plan, today: today) {
                    Button { openJourney(.reports) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(theme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your week \(week) report is ready").font(.headline).foregroundStyle(theme.text)
                                Text("Built from what you checked in.").font(.footnote).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(theme.muted)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("report.ready")
                }
                if plan.isFinished(today: today) {
                    finished
                } else if let note = milestones[dayNumber] {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Day \(dayNumber)", color: theme.gold)
                        Text(note).font(SummaFont.serifItalic(22, relativeTo: .title3))
                    }
                    .card()
                }
                if habits.isEmpty {
                    empty
                } else {
                    ForEach(habits) { habit in
                        HabitHeatmapCard(habit: habit, planStart: plan.start, today: today,
                                         onToggle: { toggle(habit, today: today) }, onOpen: { openProgress(habit) })
                    }
                    Text("The act is the record.")
                        .font(SummaFont.serifItalic(20, relativeTo: .body))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .overlay(alignment: .bottom) { undoBanner(today: today) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: undoTarget?.id)
    }

    private func header(today: DayKey, dayNumber: Int, timelines: [HabitTimeline]) -> some View {
        let stage = Stage.forDay(dayNumber)
        let overall = PlanProgress.completion(timelines: timelines, today: today)
        let percentText = overall.percent.map { "\($0)% COMPLETE" } ?? "NOTHING DUE YET"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Wordmark()
                Spacer()
                Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            Text("Keep your word.")
                .font(SummaFont.serif(38, relativeTo: .largeTitle))
                .accessibilityAddTraits(.isHeader)
            HStack {
                Text("DAY \(dayNumber) OF \(HabitTimeline.planLength) · \(stage.name.uppercased())")
                Spacer()
                Text(percentText).accessibilityIdentifier("overall.completion")
            }
            .font(.caption.weight(.medium)).tracking(1.6).foregroundStyle(theme.muted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(dayNumber) of \(HabitTimeline.planLength), \(stage.name) stage. "
                                + (overall.percent.map { "\($0) percent complete: \(overall.completed) of \(overall.scheduled) scheduled activities." } ?? "Nothing has been due yet."))
            .accessibilityIdentifier("overall.completion")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.divider)
                    Rectangle().fill(stage.color).frame(width: proxy.size.width * CGFloat(dayNumber) / CGFloat(HabitTimeline.planLength))
                }
            }
            .frame(height: 1.5)
            .accessibilityHidden(true)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Ninety days", color: theme.gold)
            Text("The plan is complete. The record stands.")
                .font(SummaFont.serif(24, relativeTo: .title3))
            Text("See your result, then choose a new chapter or continue with the same habits.")
                .font(.subheadline).foregroundStyle(theme.muted)
            Button("Open my day-90 result") { openJourney(.graduation) }
                .buttonStyle(.summaPrimary)
                .accessibilityIdentifier("finished.result")
        }
        .card()
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No active habits.").font(SummaFont.serif(24, relativeTo: .title3))
            Text("Add one from your plan to start a new record.").font(.subheadline).foregroundStyle(theme.muted)
            Button("Open plan", action: openPlan).buttonStyle(.summaSecondary)
        }
        .card()
    }

    @ViewBuilder
    private func undoBanner(today: DayKey) -> some View {
        if let habit = undoTarget {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent(habit.colorHex))
                Text("\(habit.title) marked complete").font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") {
                    PlanStore.setCompleted(false, habit: habit, day: today, in: context)
                    Haptics.undo()
                    undoTarget = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.gold)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("checkin.undo")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
            .padding(.horizontal, 16)
            .padding(.bottom, 46)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func toggle(_ habit: Habit, today: DayKey) {
        let wasCompleted = habit.completedDays.contains(today)
        PlanStore.setCompleted(!wasCompleted, habit: habit, day: today, in: context)
        if wasCompleted {
            Haptics.undo()
            undoTarget = nil
        } else {
            Haptics.complete()
            // Finishing everything due on day 90 is the moment graduation is evaluated.
            if !plan.graduationSeen, Graduation.isDue(timelines: plan.timelines, planStart: plan.start, today: today) {
                openJourney(.graduation)
            }
            undoTarget = habit
            undoToken += 1
            let token = undoToken
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if token == undoToken { undoTarget = nil }
            }
        }
    }
}

struct HabitHeatmapCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    let planStart: DayKey
    let today: DayKey
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let timeline = habit.timeline(planStart: planStart)
        let status = timeline.status(on: today, today: today)
        let accent = Color.accent(habit.colorHex)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        Image(systemName: habit.symbol)
                            .foregroundStyle(accent)
                            .frame(width: 40, height: 40)
                            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.title).font(SummaFont.serif(24, relativeTo: .title3)).foregroundStyle(theme.text)
                            Text(subtitle(status, timeline: timeline)).font(.footnote).foregroundStyle(theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens progress for this habit")
                .accessibilityIdentifier("habit.open.\(habit.title)")

                CheckButton(status: status, accent: accent, action: onToggle)
                    .accessibilityLabel(checkLabel(status))
                    .accessibilityIdentifier("checkin.\(habit.title)")
            }
            Button(action: onOpen) {
                HeatmapGrid(timeline: timeline, today: today, accent: accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens progress for this habit")
        }
        .card()
    }

    private func subtitle(_ status: DayStatus, timeline: HabitTimeline) -> String {
        switch status {
        case .pending: return habit.action
        case .completed: return "Done today."
        default:
            if let next = timeline.nextScheduledDay(after: today) { return "Rest day. Next: \(next.formatted(.dateTime.weekday(.wide)))." }
            return "No more scheduled days."
        }
    }

    private func checkLabel(_ status: DayStatus) -> String {
        switch status {
        case .pending: return "Mark \(habit.title) complete for today"
        case .completed: return "\(habit.title) completed today. Undo"
        default: return "\(habit.title): nothing due today"
        }
    }
}

/// The fastest action in the app.
struct CheckButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: DayStatus
    let accent: Color
    let action: () -> Void

    var body: some View {
        let done = status == .completed
        let enabled = status == .pending || status == .completed
        Button(action: action) {
            Image(systemName: enabled ? "checkmark" : "moon.zzz")
                .font(.body.weight(.bold))
                .foregroundStyle(done ? Color.black.opacity(0.85) : (enabled ? accent : theme.muted))
                .frame(width: 52, height: 52)
                .background(done ? accent : accent.opacity(enabled ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(enabled ? accent : theme.divider, lineWidth: done ? 0 : 1.5))
                .scaleEffect(done && !reduceMotion ? 1.04 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: done)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
