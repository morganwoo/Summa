import Foundation

/// Builds three personalized, editable habits on device from onboarding answers.
///
/// This is the profile-based engine used when the plan service is not configured,
/// is offline, or fails. It reads the person's chosen areas, the words of their
/// objective and day-90 vision, what gets in their way, their time, their days,
/// and how small they want to start, and it explains each habit in those terms.
public enum StarterPlanBuilder {
    public static func build(from answers: OnboardingAnswers) -> PlanDraft {
        let pool = candidates(for: answers)
        var habits = Array(pool.prefix(PlanSchema.initialHabits))
        for index in habits.indices { habits[index].colorHex = HabitPalette.color(at: index) }

        let objective = answers.text(.objective).isEmpty
            ? "Practice \(habits.map { $0.title.lowercased() }.joined(separator: ", ")) consistently for 90 days."
            : String(answers.text(.objective).prefix(280))

        let first = habits.first
        let obstacle = answers.selections(.obstacles).first?.lowercased()
        let phases = PhaseDraft.standard(focus: [
            "Keep it small. Do “\(first?.title ?? "your first habit")” on every scheduled day, even if only the minimum."
                + (obstacle.map { " Expect \($0); that is what the minimum is for." } ?? ""),
            "Hold the schedule steady. Raise \(first?.target ?? "the target") only once the minimum feels automatic.",
            "Decide what you keep after day 90 and make the practice your own.",
        ])
        return PlanDraft(objective: objective, habits: habits, phases: phases, source: "starter")
    }

    /// A different recommendation for one slot: the next candidate that is not already in the plan.
    /// Repeated calls walk through the pool, so the person can keep asking.
    public static func replacement(for habit: HabitDraft, in plan: PlanDraft, answers: OnboardingAnswers) -> HabitDraft {
        let pool = candidates(for: answers)
        let taken = Set(plan.habits.map { $0.title })
        let start = pool.firstIndex { $0.title == habit.title }.map { $0 + 1 } ?? 0
        let rotated = Array(pool[min(start, pool.count)...] + pool[..<min(start, pool.count)])
        guard var next = rotated.first(where: { !taken.contains($0.title) }) else { return habit }
        next.id = habit.id
        next.colorHex = habit.colorHex
        return next
    }

    // MARK: Profile

    struct Profile {
        var areas: [String]
        var minutes: Int
        var days: [Int]
        var anchor: ReminderDraft
        var timeOfDay: String
        var objective: String
        var obstacles: Set<String>
        var size: String
    }

    static let keywords: [(area: String, words: [String])] = [
        ("Reading", ["read", "book", "novel", "pages", "literature"]),
        ("Movement", ["run", "gym", "weight", "fit", "strength", "exercise", "train", "walk", "marathon", "muscle", "yoga", "swim", "body", "health"]),
        ("Sleep routine", ["sleep", "tired", "wake", "bed", "rest", "insomnia", "early"]),
        ("Focus", ["focus", "study", "exam", "work", "write", "code", "project", "business", "thesis", "learn", "career", "build", "finish", "course", "degree"]),
        ("Reflection", ["calm", "anx", "stress", "meditat", "journal", "mind", "present", "patien", "grat", "peace", "reflect", "stoic"]),
    ]

    static func profile(from answers: OnboardingAnswers) -> Profile {
        let written = (answers.text(.objective) + " " + answers.text(.future) + " " + answers.text(.extra)).lowercased()
        // A custom area the person typed is read for what it is about, so a sentence such as
        // "more time studying instead of gaming" becomes a Focus habit instead of a habit named after the sentence.
        var areas: [String] = []
        for area in answers.focusAreas {
            var resolved = area
            if !OnboardingFlow.focusOptions.contains(area) {
                let text = area.lowercased()
                if let match = keywords.first(where: { entry in entry.words.contains(where: { text.contains($0) }) }) {
                    resolved = match.area
                } else if area.split(separator: " ").count > 4 {
                    continue // a sentence that names no practice: the written objective still shapes the plan
                }
            }
            if !areas.contains(resolved) { areas.append(resolved) }
        }
        // Areas the person wrote about but did not tick come next.
        for entry in keywords where !areas.contains(entry.area) && entry.words.contains(where: { written.contains($0) }) {
            areas.append(entry.area)
        }
        let obstacles = Set(answers.selections(.obstacles))
        // Then areas that answer their obstacles, then the rest, so there are always enough.
        var fallbacks: [String] = []
        if obstacles.contains("Phone and distractions") { fallbacks.append("Focus") }
        if obstacles.contains("Low energy") { fallbacks += ["Sleep routine", "Movement"] }
        if obstacles.contains("Losing interest") { fallbacks.append("Reflection") }
        fallbacks += ["Reflection", "Focus", "Movement", "Reading", "Sleep routine"]
        for area in fallbacks where !areas.contains(area) { areas.append(area) }

        let size = answers.text(.startSize)
        var factor: Double = size.hasPrefix("Tiny") ? 0.5 : (size.hasPrefix("Ambitious") ? 1.0 : 0.75)
        if obstacles.contains("Starting too big") || obstacles.contains("Not enough time") { factor *= 0.8 }
        let perHabit = max(2, Int((Double(answers.minutesPerDay) * factor / 3).rounded()))
        let timeOfDay = answers.text(.timeOfDay).isEmpty ? "Evening" : answers.text(.timeOfDay)
        return Profile(areas: areas, minutes: roundToFriendly(perHabit), days: answers.weekdays,
                       anchor: reminder(for: timeOfDay), timeOfDay: timeOfDay,
                       objective: answers.text(.objective).trimmed, obstacles: obstacles, size: size)
    }

    /// Ordered pool of distinct habits for this person: their areas first, each with a second variant further down.
    static func candidates(for answers: OnboardingAnswers) -> [HabitDraft] {
        let p = profile(from: answers)
        var pool: [HabitDraft] = []
        var seen = Set<String>()
        for variant in 0..<2 {
            for (rank, area) in p.areas.enumerated() {
                guard var habit = template(area: area, variant: variant, profile: p) else { continue }
                guard seen.insert(habit.title).inserted else { continue }
                habit.reason = reason(for: area, rank: rank, chosen: answers.focusAreas.contains(area), profile: p)
                pool.append(habit)
            }
        }
        return pool
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

    // MARK: Explanations

    static func reason(for area: String, rank: Int, chosen: Bool, profile p: Profile) -> String {
        var parts: [String] = []
        let goal = p.objective.isEmpty ? nil : "“\(String(p.objective.prefix(80)))”"
        if chosen {
            parts.append(goal.map { "You chose \(area.lowercased()), and it moves you toward \($0)." } ?? "You chose \(area.lowercased()) as something to practice.")
        } else if let goal {
            parts.append("Suggested because it supports \(goal).")
        } else {
            parts.append("Suggested to round out your plan.")
        }
        if p.obstacles.contains("Phone and distractions"), ["Focus", "Reading", "Sleep routine"].contains(area) {
            parts.append("You said your phone gets in the way, so it stays out of reach for this one.")
        } else if p.obstacles.contains("Low energy"), ["Movement", "Sleep routine"].contains(area) {
            parts.append("You mentioned low energy; this is one of the few habits that gives some back.")
        } else if p.obstacles.contains("Not enough time") {
            parts.append("Time is tight for you, so it is sized at \(p.minutes) minutes and placed in the \(p.timeOfDay.lowercased()).")
        } else if p.obstacles.contains("Starting too big") {
            parts.append("You tend to start too big, so the target is deliberately modest and the minimum is tiny.")
        } else if p.obstacles.contains("An unpredictable schedule") {
            parts.append("Your days are unpredictable, so the minimum version fits into any gap.")
        } else if p.obstacles.contains("Losing interest") {
            parts.append("Interest fades for you, so the target grows across the three phases to keep it fresh.")
        } else {
            parts.append("It is set for the \(p.timeOfDay.lowercased()), when you said you follow through.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Templates

    static func template(area: String, variant: Int, profile p: Profile) -> HabitDraft? {
        let m = p.minutes
        let phoneAway = p.obstacles.contains("Phone and distractions")
        let subject = p.objective.isEmpty ? "the one thing that matters most" : "“\(String(p.objective.prefix(60)))”"
        let when = p.timeOfDay == "Morning" ? "before the day starts" : (p.timeOfDay == "Midday" ? "at midday" : "in the evening")
        switch (area, variant) {
        case ("Focus", 0):
            return HabitDraft(title: "One focused block",
                              action: "Work on \(subject) for \(m) minutes \(when)" + (phoneAway ? ", phone in another room" : ""),
                              minimumVersion: "Two minutes on it, then decide whether to continue", target: "\(m) minutes",
                              weekdays: p.days, reminder: p.anchor, symbol: "scope")
        case ("Focus", 1):
            return HabitDraft(title: "Plan tomorrow tonight", action: "Write tomorrow’s single most important task before you stop for the day",
                              minimumVersion: "Write one line", target: "1 task written", weekdays: p.days,
                              reminder: ReminderDraft(hour: 20, minute: 30), symbol: "list.bullet")
        case ("Movement", 0):
            return HabitDraft(title: "Train the body", action: "Move for \(m) minutes \(when): walk, lift, or stretch",
                              minimumVersion: "Put on your shoes and walk for two minutes", target: "\(m) minutes",
                              weekdays: p.days, reminder: p.anchor, symbol: "figure.walk")
        case ("Movement", 1):
            return HabitDraft(title: "Walk outside", action: "Walk outdoors for \(max(5, m)) minutes without headphones",
                              minimumVersion: "Step outside and walk to the corner and back", target: "\(max(5, m)) minutes",
                              weekdays: p.days, reminder: ReminderDraft(hour: 12, minute: 30), symbol: "leaf")
        case ("Reading", 0):
            let pages = max(2, m / 2)
            return HabitDraft(title: "Read daily", action: "Read \(pages) pages of a book \(when), away from a screen",
                              minimumVersion: "Read one page", target: "\(pages) pages", weekdays: p.days, reminder: p.anchor, symbol: "book")
        case ("Reading", 1):
            return HabitDraft(title: "Note one idea", action: "After reading, write down one idea worth keeping",
                              minimumVersion: "Underline one sentence", target: "1 idea", weekdays: p.days, reminder: p.anchor, symbol: "pencil.line")
        case ("Sleep routine", 0):
            let lead = max(15, m)
            return HabitDraft(title: "Evening wind-down", action: "Screens off \(lead) minutes before bed" + (phoneAway ? ", phone charging outside the bedroom" : ""),
                              minimumVersion: "Leave your phone out of reach when you lie down", target: "\(lead) screen-free minutes",
                              weekdays: [1, 2, 3, 4, 5, 6, 7], reminder: ReminderDraft(hour: 21, minute: 30), symbol: "moon")
        case ("Sleep routine", 1):
            return HabitDraft(title: "Rise at a set time", action: "Get up at the same time on every scheduled day",
                              minimumVersion: "Feet on the floor within five minutes of the alarm", target: "Up within 5 minutes",
                              weekdays: p.days, reminder: ReminderDraft(hour: 6, minute: 45), symbol: "sun.max")
        case ("Reflection", 0):
            return HabitDraft(title: "Evening review", action: "Write three lines about the day: what went well, what did not, what is next",
                              minimumVersion: "Write one honest sentence", target: "3 lines", weekdays: p.days,
                              reminder: ReminderDraft(hour: 21, minute: 0), symbol: "pencil.line")
        case ("Reflection", 1):
            return HabitDraft(title: "Morning intention", action: "Before the day begins, name the one thing within your control that matters today",
                              minimumVersion: "Say it aloud once", target: "1 intention", weekdays: p.days,
                              reminder: ReminderDraft(hour: 7, minute: 0), symbol: "sun.max")
        case (_, 0) where !OnboardingFlow.focusOptions.contains(area):
            let name = String(area.trimmed.prefix(48))
            guard !name.isEmpty else { return nil }
            return HabitDraft(title: name, action: "Practice \(name.lowercased()) for \(m) minutes \(when)",
                              minimumVersion: "Two minutes of \(name.lowercased())", target: "\(m) minutes",
                              weekdays: p.days, reminder: p.anchor, symbol: "laurel.leading")
        default:
            return nil
        }
    }
}
