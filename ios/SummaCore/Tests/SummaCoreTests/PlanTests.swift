import Foundation
import Testing
@testable import SummaCore

private func habit(_ title: String = "Read daily", weekdays: [Int] = [2, 3, 4, 5, 6]) -> HabitDraft {
    HabitDraft(title: title, action: "Read two pages after breakfast", minimumVersion: "Read one page", weekdays: weekdays)
}

@Suite struct PlanValidationTests {
    @Test func acceptsAWellFormedPlanAndNormalizesIt() throws {
        var h = habit(" Read daily ", weekdays: [6, 2, 2, 4])
        h.colorHex = "not-a-color"
        let plan = try PlanDraft(objective: "  Read more.  ", habits: [h, habit("Train"), habit("Reflect")]).validated()
        #expect(plan.objective == "Read more.")
        #expect(plan.habits[0].title == "Read daily")
        #expect(plan.habits[0].weekdays == [2, 4, 6])
        #expect(HabitPalette.isValidHex(plan.habits[0].colorHex))
        #expect(plan.phases.map { $0.title } == ["Foundation", "Momentum", "Transformation"])
        #expect(plan.phases.map { $0.stage } == [.foundation, .momentum, .transformation])
    }

    @Test func aNewPlanHasExactlyThreeHabits() {
        for count in [0, 1, 2, 4, 5] {
            let plan = PlanDraft(objective: "x", habits: (0..<count).map { habit("H\($0)") })
            var caught: PlanValidationError?
            do { _ = try plan.validated() } catch { caught = error as? PlanValidationError }
            #expect(caught == .habitCount(count))
        }
    }

    @Test func rejectsBadFields() {
        func error(_ mutate: (inout PlanDraft) -> Void) -> PlanValidationError? {
            var plan = PlanDraft(objective: "Read more", habits: [habit(), habit("Train"), habit("Reflect")])
            mutate(&plan)
            do { _ = try plan.validated(); return nil } catch { return error as? PlanValidationError }
        }
        #expect(error { $0.objective = "   " } == .emptyObjective)
        #expect(error { $0.schemaVersion = 2 } == .unsupportedVersion(2))
        #expect(error { $0.habits[1].weekdays = [] } == .habitField(index: 1, field: "schedule"))
        #expect(error { $0.habits[0].weekdays = [0, 8] } == .habitField(index: 0, field: "schedule"))
        #expect(error { $0.habits[0].minimumVersion = "" } == .habitField(index: 0, field: "minimum version"))
        #expect(error { $0.habits[0].reminder = ReminderDraft(hour: 24, minute: 0) } == .habitField(index: 0, field: "reminder"))
        #expect(error { $0.phases[1].startDay = 30 } == .phases)
        #expect(error { $0.phases.removeLast() } == .phases)
        #expect(error { _ in } == nil)
    }

    @Test func decodesServerJSONWithoutClientOnlyFields() throws {
        let json = """
        {"schemaVersion":1,"objective":"Sleep by eleven","habits":[
          {"title":"Wind down","action":"Screens off at 10:15pm","minimumVersion":"Phone across the room","weekdays":[1,2,3,4,5,6,7],"reminder":{"hour":22,"minute":0}},
          {"title":"Morning light","action":"Ten minutes outside after waking","minimumVersion":"Open the curtains","weekdays":[2,3,4,5,6]},
          {"title":"Read","action":"Read ten pages","minimumVersion":"One page","target":"10 pages","reason":"You said you want to read more.","weekdays":[2,3,4,5,6]}
        ],"phases":[
          {"title":"Find your footing","startDay":1,"endDay":21,"focus":"a"},
          {"title":"Settle into rhythm","startDay":22,"endDay":66,"focus":"b"},
          {"title":"Make it yours","startDay":67,"endDay":90,"focus":"c"}]}
        """
        let plan = try JSONDecoder().decode(PlanDraft.self, from: Data(json.utf8)).validated()
        #expect(plan.habits.count == 3)
        #expect(plan.habits[2].target == "10 pages")
        #expect(plan.habits[2].reason == "You said you want to read more.")
        #expect(plan.habits[0].target == "")
        #expect(plan.habits[0].reminder == ReminderDraft(hour: 22, minute: 0))
        #expect(plan.habits[1].reminder == nil)
        #expect(plan.source == "ai")
    }
}

@Suite struct OnboardingTests {
    @Test func answersSurviveEncodingSoOnboardingCanResume() throws {
        var a = OnboardingAnswers()
        a.set(.name, text: "  Alex ")
        a.set(.focus, ["Reading", "Movement"])
        a.currentStep = .obstacles
        a.mode = "talk"
        let restored = try JSONDecoder().decode(OnboardingAnswers.self, from: JSONEncoder().encode(a))
        #expect(restored == a)
        #expect(restored.name == "Alex")
    }

    @Test func bodyStepAppearsOnlyForBodyGoals() {
        var a = OnboardingAnswers()
        a.set(.focus, ["Reading"])
        #expect(!OnboardingFlow.steps(for: a).contains(.body))
        #expect(OnboardingFlow.next(after: .startSize, answers: a) == .future)
        a.set(.focus, ["Reading", "Movement"])
        #expect(OnboardingFlow.next(after: .startSize, answers: a) == .body)
        #expect(OnboardingFlow.previous(before: .future, answers: a) == .body)
        #expect(OnboardingFlow.question(.body, answers: a).isOptional)
    }

    @Test func requiredQuestionsBlockContinueUntilAnswered() {
        var a = OnboardingAnswers()
        #expect(!OnboardingFlow.canContinue(.name, answers: a))
        a.set(.name, text: "Alex")
        #expect(OnboardingFlow.canContinue(.name, answers: a))
        #expect(OnboardingFlow.canContinue(.extra, answers: a))
        #expect(OnboardingFlow.canContinue(.arc, answers: a))
        #expect(OnboardingFlow.question(.motivation, answers: a).prompt == "What brought you here, Alex?")
        #expect(OnboardingFlow.next(after: .extra, answers: a) == nil)
        #expect(OnboardingFlow.previous(before: .name, answers: a) == nil)
    }

    @Test func describesSchedulesInPlainWords() {
        #expect(OnboardingFlow.describe(weekdays: [2, 3, 4, 5, 6]) == "Weekdays")
        #expect(OnboardingFlow.describe(weekdays: [1, 2, 3, 4, 5, 6, 7]) == "Every day")
        #expect(OnboardingFlow.describe(weekdays: [1, 2, 4]) == "Mon, Wed, Sun")
        #expect(OnboardingFlow.describe(weekdays: [7, 1]) == "Weekends")
    }
}

@Suite struct UsernameTests {
    @Test func acceptsValidNamesAndNormalizesCase() {
        for name in ["alex", "alex_92", "a1b", "Marcus_Aurelius", "  seneca  "] {
            #expect(UsernameRule.problem(with: name) == nil)
        }
        #expect(UsernameRule.normalized("  Marcus_A ") == "marcus_a")
    }

    @Test func rejectsInvalidNames() {
        for name in ["", "ab", "1alex", "_alex", "alex_", "al__ex", "alex!", "al ex", "álex", "summa", String(repeating: "a", count: 21)] {
            #expect(UsernameRule.problem(with: name) != nil)
        }
    }

    @Test func onboardingWaitsForAValidUsername() {
        var a = OnboardingAnswers()
        a.set(.name, text: "Alex")
        #expect(OnboardingFlow.next(after: .name, answers: a) == .username)
        #expect(!OnboardingFlow.canContinue(.username, answers: a))
        a.set(.username, text: "x")
        #expect(!OnboardingFlow.canContinue(.username, answers: a))
        a.set(.username, text: "Alex_K")
        #expect(OnboardingFlow.canContinue(.username, answers: a))
        #expect(a.username == "alex_k")
    }
}

private func profile(focus: [String] = [], objective: String = "", obstacles: [String] = [], minutes: String = "20 minutes",
                     size: String = "", time: String = "", days: [String] = [], future: String = "") -> OnboardingAnswers {
    var a = OnboardingAnswers()
    a.set(.focus, focus)
    a.set(.objective, text: objective)
    a.set(.obstacles, obstacles)
    a.set(.minutes, text: minutes)
    a.set(.startSize, text: size)
    a.set(.timeOfDay, text: time)
    a.set(.days, days)
    a.set(.future, text: future)
    return a
}

@Suite struct StarterPlanTests {
    @Test func alwaysProducesExactlyThreeValidHabits() throws {
        let focusSets: [[String]] = [[], ["Reading"], ["Reflection"], ["Focus", "Movement"], ["Focus", "Movement", "Reading", "Sleep routine", "Reflection"],
                                     ["Learn the cello"], ["Learn the cello", "Paint", "Cook", "Garden"]]
        for focus in focusSets {
            for size in ["", "Tiny — almost too easy", "Ambitious — I have room for it"] {
                for obstacles in [[], ["Not enough time"], ["Phone and distractions", "Low energy"]] {
                    let plan = try StarterPlanBuilder.build(from: profile(focus: focus, obstacles: obstacles, minutes: "45 minutes or more", size: size)).validated()
                    #expect(plan.habits.count == 3)
                    #expect(Set(plan.habits.map { $0.title }).count == 3)
                    #expect(Set(plan.habits.map { $0.colorHex }).count == 3)
                    #expect(plan.habits.allSatisfy { !$0.target.isEmpty && !$0.reason.isEmpty && !$0.weekdays.isEmpty })
                }
            }
        }
    }

    @Test func respectsDaysTimeAndObjective() throws {
        let a = profile(focus: ["Reading", "Movement"], objective: "Finish four books", time: "Morning", days: ["2", "4", "6"])
        let plan = try StarterPlanBuilder.build(from: a).validated()
        #expect(plan.objective == "Finish four books")
        #expect(plan.habits[0].title == "Read daily")
        #expect(plan.habits[1].title == "Train the body")
        #expect(plan.habits[0].weekdays == [2, 4, 6])
        #expect(plan.habits[0].reminder == ReminderDraft(hour: 7, minute: 30))
        #expect(plan.habits[0].reason.contains("Finish four books"))
    }

    @Test func differentPeopleGetDifferentPlans() {
        let student = StarterPlanBuilder.build(from: profile(objective: "Pass my anatomy exam", obstacles: ["Phone and distractions"], minutes: "45 minutes or more", time: "Morning"))
        let runner = StarterPlanBuilder.build(from: profile(objective: "Run a 10k without stopping", obstacles: ["Low energy"], minutes: "30 minutes", time: "Evening"))
        let reader = StarterPlanBuilder.build(from: profile(focus: ["Reading"], objective: "Read twelve books", obstacles: ["Not enough time"], minutes: "10 minutes"))
        // Written goals choose the lead habit even when no area was ticked.
        #expect(student.habits[0].title == "One focused block")
        #expect(student.habits[0].action.contains("Pass my anatomy exam"))
        #expect(student.habits[0].action.contains("phone in another room"))
        #expect(runner.habits[0].title == "Train the body")
        #expect(runner.habits[0].reason.contains("low energy"))
        #expect(reader.habits[0].title == "Read daily")
        #expect(reader.habits[0].reason.contains("Time is tight"))
        let actions = [student, runner, reader].map { $0.habits.map { $0.action + $0.reason } }
        #expect(Set(actions).count == 3)
        #expect(Set([student, runner, reader].map { $0.habits.map { $0.title } }).count == 3)
    }

    @Test func timeAndStartSizeChangeTheTargets() {
        let small = StarterPlanBuilder.build(from: profile(focus: ["Reading"], minutes: "10 minutes", size: "Tiny — almost too easy"))
        let large = StarterPlanBuilder.build(from: profile(focus: ["Reading"], minutes: "45 minutes or more", size: "Ambitious — I have room for it"))
        #expect(small.habits[0].target == "2 pages")
        #expect(large.habits[0].target == "7 pages")
    }

    @Test func regeneratingOneHabitKeepsTheOthersAndNeverDuplicates() throws {
        let a = profile(focus: ["Reading", "Movement"], objective: "Finish four books")
        var plan = StarterPlanBuilder.build(from: a)
        let original = plan.habits
        var seen = Set([original[1].title])
        for _ in 0..<6 {
            let next = StarterPlanBuilder.replacement(for: plan.habits[1], in: plan, answers: a)
            #expect(next.id == original[1].id)
            #expect(next.colorHex == original[1].colorHex)
            #expect(next.title != plan.habits[1].title)
            #expect(!next.reason.isEmpty)
            plan.habits[1] = next
            seen.insert(next.title)
            #expect(plan.habits[0] == original[0])
            #expect(plan.habits[2] == original[2])
            #expect(Set(plan.habits.map { $0.title }).count == 3)
            _ = try plan.validated()
        }
        #expect(seen.count >= 4)
    }

    @Test func freeTierAllowsThreeActiveHabits() {
        #expect(HabitLimit.canAddHabit(activeCount: 2, isPro: false))
        #expect(!HabitLimit.canAddHabit(activeCount: 3, isPro: false))
        #expect(!HabitLimit.canAddHabit(activeCount: 4, isPro: false))
        #expect(HabitLimit.canAddHabit(activeCount: 3, isPro: true))
        #expect(HabitLimit.canAddHabit(activeCount: 40, isPro: true))
    }
}

@Suite struct StageTests {
    @Test func stagesDependOnlyOnTheProgramDay() {
        #expect(Stage.forDay(1) == .foundation)
        #expect(Stage.forDay(21) == .foundation)
        #expect(Stage.forDay(22) == .momentum)
        #expect(Stage.forDay(66) == .momentum)
        #expect(Stage.forDay(67) == .transformation)
        #expect(Stage.forDay(90) == .transformation)
        #expect(Stage.forDay(0) == .foundation)
        #expect(Stage.forDay(400) == .transformation)
        #expect(Stage.allCases.map { $0.days.count }.reduce(0, +) == 90)
        #expect(Set(Stage.allCases.map { $0.accentHex }).count == 3)
    }

    @Test func eachLaterStageIsCelebratedOnce() {
        #expect(Stage.toCelebrate(current: .foundation, lastCelebrated: 0) == nil)
        #expect(Stage.toCelebrate(current: .momentum, lastCelebrated: 1) == .momentum)
        #expect(Stage.toCelebrate(current: .momentum, lastCelebrated: 2) == nil)
        #expect(Stage.toCelebrate(current: .transformation, lastCelebrated: 2) == .transformation)
        // Opening the app for the first time in weeks celebrates only the stage you are in.
        #expect(Stage.toCelebrate(current: .transformation, lastCelebrated: 1) == .transformation)
        #expect(Stage.toCelebrate(current: .transformation, lastCelebrated: 3) == nil)
    }

    @Test func oldPhaseTitlesStillMapToStages() throws {
        let json = """
        [{"title":"Find your footing","startDay":1,"endDay":21,"focus":"a"},{"title":"Settle into rhythm","startDay":22,"endDay":66,"focus":"b"},{"title":"Make it yours","startDay":67,"endDay":90,"focus":"c"}]
        """
        let phases = try JSONDecoder().decode([PhaseDraft].self, from: Data(json.utf8))
        #expect(phases.map { $0.stage.name } == ["Foundation", "Momentum", "Transformation"])
    }
}

@Suite struct PlanProgressTests {
    private func key(_ s: String) -> DayKey { DayKey(s)! }

    /// Two habits from Monday 2026-11-02: one daily, one on weekdays only.
    private func timelines(daily: [String], weekdays: [String]) -> [HabitTimeline] {
        let start = key("2026-11-02")
        return [
            HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)], completed: Set(daily.map { key($0) })),
            HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .weekdays)], completed: Set(weekdays.map { key($0) })),
        ]
    }

    @Test func everyKindOfDayIsDistinguished() {
        let t = timelines(daily: ["2026-11-02", "2026-11-03", "2026-11-07", "2026-11-09"], weekdays: ["2026-11-02"])
        let today = key("2026-11-09") // Monday of week two
        func status(_ s: String) -> PlanDay.Status { PlanProgress.day(key(s), timelines: t, today: today).status }
        #expect(status("2026-11-02") == .completed) // both done
        #expect(status("2026-11-03") == .partial)   // one of two
        #expect(status("2026-11-04") == .missed)    // none of two
        #expect(status("2026-11-07") == .completed) // Saturday: only the daily habit is due
        #expect(status("2026-11-08") == .missed)
        #expect(status("2026-11-09") == .current)   // today, one of two so far
        #expect(status("2026-11-10") == .upcoming)
        #expect(status("2026-11-01") == .rest)      // before the plan
        let partial = PlanProgress.day(key("2026-11-03"), timelines: t, today: today)
        #expect(partial.completed == 1)
        #expect(partial.scheduled == 2)
        #expect(partial.fraction == 0.5)
        #expect(PlanProgress.day(today, timelines: t, today: today).fraction == 0.5)
    }

    @Test func todayBecomesCompletedOnlyWhenEverythingDueIsDone() {
        let today = key("2026-11-02")
        #expect(PlanProgress.day(today, timelines: timelines(daily: [], weekdays: []), today: today).status == .current)
        #expect(PlanProgress.day(today, timelines: timelines(daily: ["2026-11-02"], weekdays: ["2026-11-02"]), today: today).status == .completed)
        #expect(PlanProgress.day(today, timelines: [], today: today).status == .rest)
    }

    @Test func overallCompletionUsesRealRecordsAcrossHabits() {
        let t = timelines(daily: ["2026-11-02", "2026-11-03", "2026-11-07"], weekdays: ["2026-11-02"])
        // Through Sunday Nov 8: daily habit 7 scheduled, weekday habit 5 scheduled; 3 + 1 completed.
        let result = PlanProgress.completion(timelines: t, today: key("2026-11-08"))
        #expect(result.completed == 4)
        #expect(result.scheduled == 12)
        #expect(result.percent == 33)
        #expect(PlanProgress.completion(timelines: [], today: key("2026-11-08")).percent == nil)
    }
}
