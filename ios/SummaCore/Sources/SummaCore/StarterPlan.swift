import Foundation

/// Builds a sensible, editable plan on device from onboarding answers.
/// Used when the plan service is not configured, is offline, or fails, so a
/// person can always leave onboarding with a plan.
public enum StarterPlanBuilder {
    public static func build(from answers: OnboardingAnswers) -> PlanDraft {
        var areas = Array(answers.focusAreas.prefix(3))
        if areas.isEmpty { areas = ["Focus", "Reflection"] }
        if areas.count == 1 { areas.append(areas[0] == "Reflection" ? "Focus" : "Reflection") }

        let size = answers.text(.startSize)
        let factor: Double = size.hasPrefix("Tiny") ? 0.5 : (size.hasPrefix("Ambitious") ? 1.0 : 0.75)
        let perHabit = max(2, Int((Double(answers.minutesPerDay) * factor / Double(areas.count)).rounded()))
        let minutes = roundToFriendly(perHabit)
        let anchor = reminder(for: answers.text(.timeOfDay))
        let days = answers.weekdays

        var habits: [HabitDraft] = []
        for (index, area) in areas.enumerated() {
            var habit = template(for: area, minutes: minutes, days: days, anchor: anchor)
            habit.colorHex = HabitPalette.color(at: index)
            habits.append(habit)
        }

        let objective = answers.text(.objective).isEmpty
            ? "Practice \(areas.map { $0.lowercased() }.joined(separator: " and ")) consistently for 90 days."
            : String(answers.text(.objective).prefix(280))

        let first = habits.first?.title.lowercased() ?? "your first habit"
        let phases = PhaseDraft.standard(focus: [
            "Keep it small. Show up for \(first) on every scheduled day, even with the minimum version.",
            "Hold the schedule steady. Add time only when the minimum feels automatic.",
            "Decide what you keep after day 90, and make the practice your own.",
        ])
        return PlanDraft(objective: objective, habits: habits, phases: phases, source: "starter")
    }

    static func roundToFriendly(_ minutes: Int) -> Int {
        for step in [2, 5, 10, 15, 20, 30, 45] where minutes <= step { return step }
        return 45
    }

    static func reminder(for timeOfDay: String) -> ReminderDraft {
        switch timeOfDay {
        case "Morning": return ReminderDraft(hour: 7, minute: 30)
        case "Midday": return ReminderDraft(hour: 12, minute: 30)
        default: return ReminderDraft(hour: 19, minute: 30)
        }
    }

    static func template(for area: String, minutes: Int, days: [Int], anchor: ReminderDraft) -> HabitDraft {
        switch area {
        case "Focus":
            return HabitDraft(title: "One focused block", action: "Work on one thing for \(minutes) minutes with your phone in another room",
                              minimumVersion: "Two minutes on the one thing that matters", weekdays: days, reminder: anchor, symbol: "scope")
        case "Movement":
            return HabitDraft(title: "Train the body", action: "Move for \(minutes) minutes — walk, lift, or stretch",
                              minimumVersion: "Put on your shoes and walk for two minutes", weekdays: days, reminder: anchor, symbol: "figure.walk")
        case "Reading":
            let pages = max(2, minutes / 2)
            return HabitDraft(title: "Read daily", action: "Read \(pages) pages of a book, away from a screen",
                              minimumVersion: "Read one page", weekdays: days, reminder: anchor, symbol: "book")
        case "Sleep routine":
            return HabitDraft(title: "Evening wind-down", action: "Screens off \(max(15, minutes)) minutes before bed",
                              minimumVersion: "Leave your phone out of reach when you lie down", weekdays: [1, 2, 3, 4, 5, 6, 7],
                              reminder: ReminderDraft(hour: 21, minute: 30), symbol: "moon")
        case "Reflection":
            return HabitDraft(title: "Evening review", action: "Write three lines about the day: what went well, what did not, what is next",
                              minimumVersion: "Write one honest sentence", weekdays: days,
                              reminder: ReminderDraft(hour: 21, minute: 0), symbol: "pencil.line")
        default:
            let name = String(area.trimmed.prefix(48))
            return HabitDraft(title: name, action: "Practice \(name.lowercased()) for \(minutes) minutes",
                              minimumVersion: "Two minutes of \(name.lowercased())", weekdays: days, reminder: anchor, symbol: "laurel.leading")
        }
    }
}
