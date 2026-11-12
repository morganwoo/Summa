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

@Suite struct ReminderPlannerTests {
    private func request(_ title: String, days: [Int] = [2, 3, 4, 5, 6], enabled: Bool = true, hour: Int = 8, second: Bool = false) -> ReminderRequest {
        ReminderRequest(habitID: UUID(), title: title, body: "Do it", weekdays: days, enabled: enabled, hour: hour, minute: 30,
                        secondEnabled: second, secondHour: 20, secondMinute: 0)
    }

    @Test func freeGetsOneBasicReminder() {
        let plan = ReminderPlanner.plan([request("A", enabled: false), request("B", second: true), request("C")], isPro: false)
        #expect(plan.scheduled.count == 5) // B on five weekdays, first time only
        #expect(Set(plan.scheduled.map { $0.title }) == ["B"])
        #expect(plan.scheduled.allSatisfy { $0.hour == 8 && $0.minute == 30 })
        #expect(plan.pausedHabits == 1)
        #expect(ReminderPlanner.canEnableReminder(othersEnabled: 0, isPro: false))
        #expect(!ReminderPlanner.canEnableReminder(othersEnabled: 1, isPro: false))
        #expect(ReminderPlanner.canEnableReminder(othersEnabled: 9, isPro: true))
    }

    @Test func proGetsEveryHabitAndSecondTimes() {
        let plan = ReminderPlanner.plan([request("A"), request("B", second: true), request("C", enabled: false)], isPro: true)
        #expect(plan.scheduled.count == 15) // A x5, B x5 twice
        #expect(plan.pausedHabits == 0)
        #expect(plan.scheduled.filter { $0.hour == 20 }.count == 5)
    }

    @Test func identifiersAreUniqueAndStableSoNothingDuplicates() {
        let requests = [request("A", second: true), request("B", days: [1, 2, 3, 4, 5, 6, 7], second: true)]
        let first = ReminderPlanner.plan(requests, isPro: true)
        let second = ReminderPlanner.plan(requests, isPro: true)
        #expect(first == second)
        #expect(Set(first.scheduled.map { $0.identifier }).count == first.scheduled.count)
    }

    @Test func dailyHabitsUseOneRepeatingNotification() {
        let plan = ReminderPlanner.plan([request("Daily", days: [1, 2, 3, 4, 5, 6, 7])], isPro: false)
        #expect(plan.scheduled.count == 1)
        #expect(plan.scheduled[0].weekday == nil)
    }

    @Test func scheduleChangesAndBadInputAreHandled() {
        var r = request("A", days: [2, 4])
        #expect(ReminderPlanner.plan([r], isPro: false).scheduled.map { $0.weekday } == [2, 4])
        r.weekdays = [6, 6, 9, 0]
        #expect(ReminderPlanner.plan([r], isPro: false).scheduled.map { $0.weekday } == [6])
        r.weekdays = []
        #expect(ReminderPlanner.plan([r], isPro: false).scheduled.isEmpty)
        // A second time equal to the first is not scheduled twice.
        var same = request("B", second: true)
        same.secondHour = 8
        same.secondMinute = 30
        #expect(ReminderPlanner.plan([same], isPro: true).scheduled.count == 5)
    }

    @Test func staysUnderTheSystemLimit() {
        let many = (0..<20).map { request("H\($0)", days: [1, 2, 3, 4, 5, 6], second: true) }
        let plan = ReminderPlanner.plan(many, isPro: true)
        #expect(plan.scheduled.count == ReminderPlanner.maxPending)
        #expect(plan.droppedForLimit == 20 * 12 - ReminderPlanner.maxPending)
    }

    @Test func widgetSnapshotReportsDayAndDaysRemaining() throws {
        let start = DayKey("2026-11-02")!
        let timeline = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)])
        let snapshot = WidgetSnapshot(habits: [.init(id: UUID(), title: "A", colorHex: "#DCAF61", symbol: "book", timeline: timeline)],
                                      isWhiteMarble: false, isPro: true, allTimelines: [timeline])
        #expect(snapshot.dayNumber(today: start.adding(23)) == 24)
        #expect(snapshot.daysRemaining(today: start.adding(23)) == 66)
        #expect(snapshot.daysRemaining(today: start.adding(89)) == 0)
        #expect(snapshot.daysRemaining(today: start.adding(200)) == 0)
        // Snapshots written before subscriptions existed still decode, and count as not Pro.
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: Data("{\"habits\":[],\"isWhiteMarble\":true}".utf8))
        #expect(old.isPro == nil)
        #expect(old.dayNumber(today: start) == nil)
    }
}

@Suite struct JourneyTests {
    private func key(_ s: String) -> DayKey { DayKey(s)! }
    private var start: DayKey { key("2026-11-02") } // a Monday

    private func record(_ title: String, days: WeekdaySet = .everyDay, done: [Int]) -> HabitRecord {
        HabitRecord(id: UUID(), title: title, minimumVersion: "the minimum",
                    timeline: HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: days)],
                                            completed: Set(done.map { start.adding($0) })))
    }

    @Test func weeksCoverTheNinetyDaysAndAppearOnlyWhenFinished() {
        #expect(ReportBuilder.range(week: 1, planStart: start) == start...start.adding(6))
        #expect(ReportBuilder.range(week: 13, planStart: start) == start.adding(84)...start.adding(89))
        #expect(ReportBuilder.finishedWeeks(planStart: start, today: start.adding(6)).isEmpty)
        #expect(ReportBuilder.finishedWeeks(planStart: start, today: start.adding(7)) == [1])
        #expect(ReportBuilder.finishedWeeks(planStart: start, today: start.adding(21)) == [3, 2, 1])
        #expect(ReportBuilder.finishedWeeks(planStart: start, today: start.adding(89)).count == 12)
        #expect(ReportBuilder.finishedWeeks(planStart: start, today: start.adding(90)).count == 13)
    }

    @Test func reportCountsScheduledCompletedAndMissedFromRecords() {
        let reading = record("Read", done: [0, 1, 2, 3, 4, 5, 6])          // 7 of 7
        let training = record("Train", days: .weekdays, done: [0, 1])        // 2 of 5
        let r = ReportBuilder.report(week: 1, habits: [reading, training], today: start.adding(7))
        #expect(r.scheduled == 12)
        #expect(r.completed == 9)
        #expect(r.missed == 3)
        #expect(r.percent == 75)
        #expect(r.strongest == "Read")
        #expect(r.weakest == "Train")
        #expect(r.previousPercent == nil)
        #expect(r.change == nil)
        #expect(r.habitsToReview.isEmpty) // one bad week is not "repeatedly"
        #expect(r.suggestions.contains { $0.contains("Train") && $0.contains("the minimum") })
    }

    @Test func comparesWithThePreviousWeekAndFlagsRepeatedMisses() {
        let reading = record("Read", done: Array(0..<14))
        let training = record("Train", days: .weekdays, done: [0, 1, 7])     // 2 of 5, then 1 of 5
        let r = ReportBuilder.report(week: 2, habits: [reading, training], today: start.adding(14))
        #expect(r.previousPercent == 75)
        #expect(r.percent == 67)
        #expect(r.change == -8)
        #expect(r.habitsToReview == [training.id])
        #expect(r.suggestions.contains { $0.contains("two weeks running") && $0.contains("Nothing changes unless you edit it") })
    }

    @Test func aPerfectWeekAndAnEmptyWeekReadSensibly() {
        let perfect = ReportBuilder.report(week: 1, habits: [record("Read", done: Array(0..<7))], today: start.adding(7))
        #expect(perfect.percent == 100)
        #expect(perfect.weakest == nil)
        #expect(perfect.suggestions == ["A strong week. Keep the schedule exactly as it is."])
        let empty = ReportBuilder.report(week: 1, habits: [], today: start.adding(7))
        #expect(empty.percent == nil)
        #expect(empty.suggestions == ["Nothing was due this week."])
    }

    @Test func namesTheWeekdayThatCostTheMost() {
        // Two habits both missed on Friday (index 4) only.
        let a = record("A", done: [0, 1, 2, 3, 5, 6])
        let b = record("B", done: [0, 1, 2, 3, 5, 6])
        let r = ReportBuilder.report(week: 1, habits: [a, b], today: start.adding(7))
        #expect(r.suggestions.contains { $0.contains("Friday") })
    }

    @Test func graduationNeedsEightyPercentOfAllScheduledActivities() {
        func timeline(_ count: Int, days: WeekdaySet = .everyDay) -> HabitTimeline {
            var t = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: days)])
            t.completed = Set(t.days.filter { t.isScheduled($0) }.prefix(count))
            return t
        }
        #expect(Graduation.evaluate(timelines: [timeline(72)]) == GraduationResult(completed: 72, scheduled: 90, percent: 80, eligible: true))
        let short = Graduation.evaluate(timelines: [timeline(71)])
        #expect(short.percent == 78)
        #expect(!short.eligible)
        // Non-daily habits count only their own scheduled days: 90 daily + 65 weekday occurrences.
        let mixed = Graduation.evaluate(timelines: [timeline(90), timeline(34, days: .weekdays)])
        #expect(mixed.scheduled == 155)
        #expect(mixed.completed == 124)
        #expect(mixed.eligible)                       // 124/155 is exactly 80%
        #expect(!Graduation.evaluate(timelines: [timeline(90), timeline(33, days: .weekdays)]).eligible) // 79.4% does not round up
        #expect(!Graduation.evaluate(timelines: []).eligible)
    }

    @Test func graduationCountsHistoricalScheduleChangesAndArchivedHabits() {
        // Daily for 30 days, then weekdays only: the first 30 days still count as daily.
        var changed = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay),
                                                              ScheduleRule(effectiveFrom: start.adding(30), weekdays: .weekdays)])
        let scheduledDays = changed.days.filter { changed.isScheduled($0) }
        #expect(scheduledDays.count == 30 + 43)
        changed.completed = Set(scheduledDays)
        var archived = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)])
        archived.archivedOn = start.adding(10) // ten scheduled days, none done
        let result = Graduation.evaluate(timelines: [changed, archived])
        #expect(result.scheduled == 83)
        #expect(result.completed == 73)
        #expect(result.eligible) // 88%
    }

    @Test func graduationIsEvaluatedOnceDayNinetyIsFinished() {
        var t = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)])
        let last = start.adding(89)
        #expect(!Graduation.isDue(timelines: [t], planStart: start, today: last.adding(-1)))
        #expect(!Graduation.isDue(timelines: [t], planStart: start, today: last))      // day 90 still open
        t.completed = [last]
        #expect(Graduation.isDue(timelines: [t], planStart: start, today: last))       // all of day 90 done
        t.completed = []
        #expect(Graduation.isDue(timelines: [t], planStart: start, today: last.adding(1)))
    }

    @Test func milestonesUseThePersonsObjective() {
        let m = MilestoneBuilder.defaults(objective: "Run a 10k", firstHabit: "Train the body", target: "20 minutes")
        #expect(m.map { $0.day } == [21, 66, 90])
        #expect(m.allSatisfy { $0.text.contains("Run a 10k") })
        #expect(m[0].text.contains("Train the body") && m[0].text.contains("20 minutes"))
        #expect(MilestoneBuilder.defaults(objective: " ", firstHabit: "", target: "")[2].text.contains("your objective"))
    }
}
