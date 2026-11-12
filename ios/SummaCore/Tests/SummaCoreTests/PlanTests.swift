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
    @Test func aTypedSentenceIsNeverUsedAsAHabitTitle() throws {
        var answers = OnboardingAnswers()
        let sentence = "Spending more time studying instead of playing video games"
        answers.set(.focus, [sentence])
        answers.set(.objective, text: "Lose 10 lbs, get a FAANG internship")
        let plan = try StarterPlanBuilder.build(from: answers).validated()
        #expect(plan.habits.count == 3)
        #expect(!plan.habits.contains { $0.title == String(sentence.prefix(48)) })
        #expect(plan.habits.first?.title == "One focused block")

        var short = OnboardingAnswers()
        short.set(.focus, ["Piano"])
        #expect(StarterPlanBuilder.build(from: short).habits.first?.title == "Piano")
    }

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

@Suite struct SocialTests {
    private var start: DayKey { DayKey("2026-11-02")! }

    private func record(done: [Int], days: WeekdaySet = .weekdays) -> HabitRecord {
        HabitRecord(id: UUID(), title: "Read", minimumVersion: "one page",
                    timeline: HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: days)],
                                            completed: Set(done.map { start.adding($0) })))
    }

    @Test func snapshotHasOneRowPerScheduledDaySoFar() {
        let r = record(done: [0, 1, 5]) // index 5 is a Saturday: a bonus check-in, not scheduled
        let rows = SocialSnapshot.rows(for: [r], today: start.adding(8)) // second Tuesday
        #expect(rows.count == 7) // Mon–Fri, then Mon and Tue
        #expect(rows.filter { $0.done }.count == 2)
        #expect(Set(rows.map { $0.day }).count == rows.count) // one row per day: nothing to double count
        #expect(rows.first?.day == "2026-11-02")
        // Sending again after an undo flips the same row instead of adding one.
        let undone = SocialSnapshot.rows(for: [record(done: [1])], today: start.adding(8))
        #expect(undone.count == 7)
        #expect(undone.filter { $0.done }.count == 1)
        #expect(SocialSnapshot.rows(for: [r], today: start.adding(400)).count == 65)
    }

    @Test func leaderboardRanksByCompletedThenConsistencyAndCanSwitch() {
        let a = LeaderboardEntry(userId: UUID(), username: "alex", weekCompleted: 10, weekScheduled: 21, totalCompleted: 10, totalScheduled: 21)
        let b = LeaderboardEntry(userId: UUID(), username: "bea", weekCompleted: 7, weekScheduled: 7, totalCompleted: 7, totalScheduled: 7)
        let c = LeaderboardEntry(userId: UUID(), username: "cy", weekCompleted: 7, weekScheduled: 14, totalCompleted: 7, totalScheduled: 14)
        let d = LeaderboardEntry(userId: UUID(), username: "dee", weekCompleted: 0, weekScheduled: 0, totalCompleted: 0, totalScheduled: 0)
        #expect(Leaderboard.ranked([d, c, b, a], by: .completed).map { $0.username } == ["alex", "bea", "cy", "dee"])
        #expect(Leaderboard.ranked([d, c, b, a], by: .consistency).map { $0.username } == ["bea", "cy", "alex", "dee"])
        #expect(a.weekPercent == 48)
        #expect(d.weekPercent == nil)
        #expect(Leaderboard.weekStart(for: DayKey("2026-11-08")!).string == "2026-11-02")
        #expect(Leaderboard.weekStart(for: DayKey("2026-11-09")!).string == "2026-11-09")
    }

    @Test func leaderboardRowsDecodeFromTheServerShape() throws {
        let json = """
        [{"user_id":"00000000-0000-0000-0000-00000000000A","username":"alex_k","plan_start":"2026-11-02","week_completed":7,"week_scheduled":8,"total_completed":7,"total_scheduled":8,"is_me":true}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([LeaderboardEntry].self, from: Data(json.utf8))
        #expect(rows[0].username == "alex_k")
        #expect(rows[0].isMe)
        #expect(rows[0].weekPercent == 88)
        #expect(rows[0].dayNumber(today: DayKey("2026-11-11")!) == 10)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let row = String(data: try encoder.encode(SharedDayRow(habitId: UUID(), day: "2026-11-02", done: true)), encoding: .utf8) ?? ""
        #expect(row.contains("habit_id"))
    }

    @Test func nudgesArePresetAndActivityComesFromTheRecord() {
        #expect(NudgeMessage.allCases.count == 4)
        #expect(NudgeMessage(rawValue: "buy my course") == nil)
        let all = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)])
        func kinds(_ day: Int, _ t: HabitTimeline) -> [String] {
            ActivityBuilder.events(planStart: start, timelines: [t], chapter: 1, today: start.adding(day)).map { $0.kind == "week_complete" ? "w\($0.detail)" : $0.kind }
        }
        #expect(kinds(3, all).isEmpty)
        #expect(kinds(7, all) == ["w1"])
        #expect(kinds(21, all) == ["w1", "w2", "w3", "entered_momentum"])
        #expect(kinds(66, all).contains("entered_transformation"))
        var done = all
        done.completed = Set(done.days)
        #expect(kinds(90, done).suffix(2) == ["day_90", "graduated"])
        #expect(kinds(90, all).last == "day_90") // nothing completed: day 90 reached, no graduation
        let events = ActivityBuilder.events(planStart: start, timelines: [done], chapter: 2, today: start.adding(90))
        #expect(Set(events).count == events.count)
        #expect(events.allSatisfy { $0.chapter == 2 })
    }
}

@Suite struct FriendLimitTests {
    @Test func freeHoldsTwoFriendsAndProIsUnlimited() {
        #expect(FriendLimit.canAddFriend(acceptedCount: 0, isPro: false))
        #expect(FriendLimit.canAddFriend(acceptedCount: 1, isPro: false))
        #expect(!FriendLimit.canAddFriend(acceptedCount: 2, isPro: false))
        #expect(!FriendLimit.canAddFriend(acceptedCount: 5, isPro: false)) // lapsed Pro keeps friends, cannot add
        #expect(FriendLimit.canAddFriend(acceptedCount: 50, isPro: true))
    }

    @Test func counterReadsNaturally() {
        #expect(FriendLimit.counterText(acceptedCount: 1, isPro: false) == "1 of 2 friends")
        #expect(FriendLimit.counterText(acceptedCount: 2, isPro: false) == "2 of 2 friends")
        #expect(FriendLimit.counterText(acceptedCount: 5, isPro: true) == "5 friends")
        #expect(FriendLimit.counterText(acceptedCount: 1, isPro: true) == "1 friend")
        #expect(FriendLimit.counterText(acceptedCount: 4, isPro: false) == "4 of 2 friends")
    }
}

@Suite struct AuthCallbackTests {
    private func parse(_ text: String) -> AuthCallback? { AuthCallback.parse(URL(string: text)!) }

    @Test func aCodeInTheQueryIsAccepted() {
        #expect(parse("summa://auth/callback?code=3f2a9c1e-77aa-4b1c-9d0e-5a6b7c8d9e0f") == .code("3f2a9c1e-77aa-4b1c-9d0e-5a6b7c8d9e0f"))
        #expect(parse("SUMMA://Auth/callback?code=abcdefgh12345678&type=signup") == .code("abcdefgh12345678"))
    }

    @Test func otherLinksAreNotAuthCallbacks() {
        #expect(parse("summa://pro") == nil)
        #expect(parse("summa://auth/other?code=abcdefgh12345678") == nil)
        #expect(parse("https://auth/callback?code=abcdefgh12345678") == nil)
        #expect(parse("summa://evil/auth/callback?code=abcdefgh12345678") == nil)
    }

    @Test func tokensPlacedInTheLinkAreRefused() {
        #expect(parse("summa://auth/callback#access_token=aaa.bbb.ccc&refresh_token=xyz&expires_in=3600") == .failed(.unusable))
        #expect(parse("summa://auth/callback?code=abcdefgh12345678#access_token=aaa.bbb.ccc") == .failed(.unusable))
    }

    @Test func errorsAreReportedWithoutUsingTheirText() {
        #expect(parse("summa://auth/callback?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired") == .failed(.expired))
        #expect(parse("summa://auth/callback#error=access_denied&error_code=otp_expired") == .failed(.expired))
        #expect(parse("summa://auth/callback?error=server_error&error_description=Call%20this%20number") == .failed(.unusable))
        #expect(parse("summa://auth/callback?error=x&code=abcdefgh12345678") == .failed(.unusable))
    }

    @Test func malformedCodesAreRefused() {
        #expect(parse("summa://auth/callback") == .failed(.unusable))
        #expect(parse("summa://auth/callback?code=") == .failed(.unusable))
        #expect(parse("summa://auth/callback?code=short") == .failed(.unusable))
        #expect(parse("summa://auth/callback?code=abc%20def%22%3Bdrop12345") == .failed(.unusable))
        #expect(parse("summa://auth/callback?code=" + String(repeating: "a", count: 600)) == .failed(.unusable))
    }
}

@Suite struct ReflectionTests {
    @Test func textIsTrimmedAndClipped() {
        #expect(ReflectionRule.normalized("  held the line today \n") == "held the line today")
        #expect(!ReflectionRule.isSavable("   \n "))
        #expect(ReflectionRule.normalized(String(repeating: "a", count: 5000)).count == ReflectionRule.maxLength)
    }

    @Test func reflectionsNeedProAndSurviveALapse() {
        #expect(ReflectionAccess.denial(isPro: false) == .proRequired)
        #expect(ReflectionAccess.denial(isPro: true) == nil)
        let saved = ["one", "two"]
        #expect(ReflectionAccess.visible(saved, isPro: false).isEmpty)
        // The same saved entries come back untouched when Pro returns.
        #expect(ReflectionAccess.visible(saved, isPro: true) == saved)
    }

    @Test func companionHasADailyAllowance() {
        #expect(CompanionLimit.remaining(usedToday: 0) == CompanionLimit.messagesPerDay)
        #expect(CompanionLimit.canSend(usedToday: CompanionLimit.messagesPerDay - 1))
        #expect(!CompanionLimit.canSend(usedToday: CompanionLimit.messagesPerDay))
        #expect(CompanionLimit.remaining(usedToday: 999) == 0)
    }

    @Test func aProposalIsOnlyADraft() throws {
        let decoded = try JSONDecoder().decode(CompanionReply.self, from: Data(#"{"reply":"That took patience.","proposedReflection":"  I stayed calm in the meeting. "}"#.utf8))
        #expect(decoded.draft == "I stayed calm in the meeting.")
        #expect(try JSONDecoder().decode(CompanionReply.self, from: Data(#"{"reply":"Tell me more.","proposedReflection":null}"#.utf8)).draft == nil)
        #expect(CompanionReply(reply: "Go on.", proposedReflection: "   ").draft == nil)
    }
}

@Suite struct DevScenarioTests {
    private func graduation(percent: Int) -> GraduationResult {
        let start = DayKey(year: 2026, month: 1, day: 5)
        let offsets = DevScenario.completedOffsets(habits: 3, resolvedDays: 90, percent: percent)
        let timelines = offsets.map { days in
            HabitTimeline(planStart: start, habitStart: start, archivedOn: nil,
                          rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)],
                          completed: Set(days.map { start.adding($0) }))
        }
        return Graduation.evaluate(timelines: timelines)
    }

    @Test func seventyNinePercentDoesNotGraduate() {
        let result = graduation(percent: 79)
        #expect(result.scheduled == 270)
        #expect(result.completed == 213)
        #expect(result.percent == 78 || result.percent == 79)
        #expect(!result.eligible)
    }

    @Test func eightyPercentGraduatesExactlyAtTheThreshold() {
        let result = graduation(percent: 80)
        #expect(result.completed == 216)
        #expect(result.percent == 80)
        #expect(result.eligible)
        #expect(!graduationOneShort())
    }

    private func graduationOneShort() -> Bool {
        // 215 of 270 is 79.6%: it must not round up into a graduation.
        GraduationResult(completed: 215, scheduled: 270, percent: 79, eligible: 215 * 100 >= Graduation.threshold * 270).eligible
    }

    @Test func aHundredPercentGraduates() {
        let result = graduation(percent: 100)
        #expect(result.completed == 270)
        #expect(result.eligible)
    }

    @Test func theThresholdFollowsScheduledActivitiesNotAFixedCount() {
        // A weekday-only habit has fewer scheduled days; 80% of those still graduates.
        let start = DayKey(year: 2026, month: 1, day: 5) // a Monday
        let rule = ScheduleRule(effectiveFrom: start, weekdays: .weekdays)
        let all = HabitTimeline(planStart: start, habitStart: start, archivedOn: nil, rules: [rule], completed: [])
        let scheduled = all.days.filter { all.status(on: $0, today: all.planEnd.adding(1)) != .unscheduled }
        let keep = DevScenario.completedCount(scheduled: scheduled.count, percent: 80)
        let done = HabitTimeline(planStart: start, habitStart: start, archivedOn: nil, rules: [rule], completed: Set(scheduled.prefix(keep)))
        let result = Graduation.evaluate(timelines: [done])
        #expect(result.scheduled == scheduled.count)
        #expect(result.scheduled < 90)
        #expect(result.eligible == (keep * 100 >= 80 * scheduled.count))
        let short = HabitTimeline(planStart: start, habitStart: start, archivedOn: nil, rules: [rule], completed: Set(scheduled.prefix(keep - 2)))
        #expect(!Graduation.evaluate(timelines: [short]).eligible)
    }

    @Test func stagesChangeOnDays22And67() {
        #expect(Stage.forDay(21) == .foundation)
        #expect(Stage.forDay(22) == .momentum)
        #expect(Stage.forDay(66) == .momentum)
        #expect(Stage.forDay(67) == .transformation)
        #expect(Stage.toCelebrate(current: .momentum, lastCelebrated: Stage.foundation.rawValue) == .momentum)
        #expect(Stage.toCelebrate(current: .momentum, lastCelebrated: Stage.momentum.rawValue) == nil)
        #expect(Stage.toCelebrate(current: .transformation, lastCelebrated: Stage.momentum.rawValue) == .transformation)
        #expect(DevScenario.presetDays == [1, 21, 22, 66, 67, 89, 90])
    }
}

@Suite struct VictoryCategoryTests {
    @Test func wordsChooseTheEmblem() {
        #expect(VictoryCategory.classify("Ran my first 10k without stopping") == .physical)
        #expect(VictoryCategory.classify("Passed my physics midterm") == .reckoning)
        #expect(VictoryCategory.classify("Solved the calculus proof on my own") == .reckoning)
        #expect(VictoryCategory.classify("Finished the biology lab report") == .science)
        #expect(VictoryCategory.classify("Read forty pages of Meditations") == .letters)
        #expect(VictoryCategory.classify("Paid off my credit card debt") == .wealth)
        #expect(VictoryCategory.classify("Got a raise after the math tutoring review") == .wealth)
    }

    @Test func anythingElseGetsTheSwords() {
        #expect(VictoryCategory.classify("Told my brother the truth") == .physical)
        #expect(VictoryCategory.classify("") == .physical)
    }

    @Test func aModelSuppliedCategoryIsOnlyUsedWhenValid() throws {
        #expect(VictoryCategory(loose: " Wealth ") == .wealth)
        #expect(VictoryCategory(loose: "astrology") == nil)
        #expect(VictoryCategory(loose: nil) == nil)
        let reply = try JSONDecoder().decode(CompanionReply.self, from: Data(#"{"reply":"Well earned.","proposedReflection":"I ran 10k.","proposedCategory":"physical"}"#.utf8))
        #expect(reply.category == .physical)
        #expect(CompanionReply(reply: "x", proposedReflection: "y", proposedCategory: "nonsense").category == nil)
        #expect(VictoryCategory.allCases.count == 5)
    }
}

@Suite struct RomanNumeralTests {
    @Test func numeralsAreWrittenCorrectly() {
        #expect(RomanNumeral.string(1) == "I")
        #expect(RomanNumeral.string(4) == "IV")
        #expect(RomanNumeral.string(9) == "IX")
        #expect(RomanNumeral.string(14) == "XIV")
        #expect(RomanNumeral.string(22) == "XXII")
        #expect(RomanNumeral.string(67) == "LXVII")
        #expect(RomanNumeral.string(90) == "XC")
        #expect(RomanNumeral.string(2026) == "MMXXVI")
        #expect(RomanNumeral.string(0) == "0")
        #expect(RomanNumeral.string(4000) == "4000")
    }
}

@Suite struct GraduationRingTests {
    private func timeline(completedDays: Int, start: DayKey) -> HabitTimeline {
        HabitTimeline(planStart: start, habitStart: start, archivedOn: nil, rules: [ScheduleRule(effectiveFrom: start, weekdays: .everyDay)],
                      completed: Set((0..<completedDays).map { start.adding($0) }))
    }

    @Test func theRingShowsCompletedOverEverythingScheduledNotDaysElapsed() {
        let start = DayKey(year: 2026, month: 1, day: 5)
        // 30 of 90 scheduled activities done: one third, whatever today's date is.
        let result = Graduation.evaluate(timelines: [timeline(completedDays: 30, start: start)])
        #expect(result.scheduled == 90)
        #expect(abs(GraduationRing.fraction(result) - 1.0 / 3.0) < 0.0001)
        #expect(!result.eligible)
        // A missed day never fills the ring; a completed one does.
        let more = Graduation.evaluate(timelines: [timeline(completedDays: 31, start: start)])
        #expect(GraduationRing.fraction(more) > GraduationRing.fraction(result))
        #expect(GraduationRing.fraction(Graduation.evaluate(timelines: [timeline(completedDays: 90, start: start)])) == 1)
        #expect(GraduationRing.fraction(GraduationResult(completed: 0, scheduled: 0, percent: 0, eligible: false)) == 0)
    }

    @Test func eligibilityIsStillEightyPercent() {
        let start = DayKey(year: 2026, month: 1, day: 5)
        #expect(Graduation.evaluate(timelines: [timeline(completedDays: 72, start: start)]).eligible)
        #expect(!Graduation.evaluate(timelines: [timeline(completedDays: 71, start: start)]).eligible)
        #expect(GraduationRing.thresholdFraction == 0.8)
    }

    @Test func theAuraBelongsToTransformationAndGrowsTowardDayNinety() {
        #expect(GraduationRing.auraIntensity(day: 1) == 0)
        #expect(GraduationRing.auraIntensity(day: 66) == 0)
        #expect(GraduationRing.auraIntensity(day: 67) > 0)
        #expect(GraduationRing.auraIntensity(day: 79) < GraduationRing.auraIntensity(day: 80) + 0.0001)
        #expect(GraduationRing.auraIntensity(day: 85) > GraduationRing.auraIntensity(day: 80))
        #expect(GraduationRing.auraIntensity(day: 90) == 1)
        #expect(GraduationRing.auraIntensity(day: 90) - GraduationRing.auraIntensity(day: 80) > GraduationRing.auraIntensity(day: 80) - GraduationRing.auraIntensity(day: 67))
        #expect(GraduationRing.auraIntensity(day: 40, finished: true) == 1)
    }

    @Test func gradientsComeFromTheStageColors() {
        for stage in Stage.allCases {
            let stops = GraduationRing.gradientHexes(for: stage)
            #expect(stops.count == 4)
            #expect(stops[1] == stage.accentHex)
            #expect(stops[0] != stage.accentHex && stops[2] != stage.accentHex)
        }
        #expect(GraduationRing.blend("#000000", toward: "#FFFFFF", by: 0.5) == "#808080")
        #expect(GraduationRing.blend("#5FAE7A", toward: "#000000", by: 0) == "#5FAE7A")
        #expect(GraduationRing.blend("nonsense", toward: "#FFFFFF", by: 0.5) == "nonsense")
    }
}

@Suite struct WidgetInboxTests {
    private let start = DayKey(year: 2026, month: 1, day: 5) // Monday
    private func snapshot(weekdays: WeekdaySet = .everyDay) -> (WidgetSnapshot, UUID) {
        let id = UUID()
        let timeline = HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: weekdays)], completed: [])
        let habit = WidgetSnapshot.Habit(id: id, title: "Read daily", colorHex: "#DCAF61", symbol: "book", timeline: timeline, detail: "Two pages")
        return (WidgetSnapshot(habits: [habit], isWhiteMarble: false, isPro: true, allTimelines: [timeline]), id)
    }

    @Test func theButtonMarksTodayAndCanUndoIt() {
        let (snap, id) = snapshot()
        let today = start.adding(3)
        guard let done = WidgetInbox.toggling(habitID: id, on: today, in: snap) else { #expect(1 == 2); return }
        #expect(done.change == PendingCheckIn(habitID: id, day: today, completed: true))
        #expect(done.snapshot.habits[0].timeline.status(on: today, today: today) == .completed)
        #expect(done.snapshot.allTimelines?[0].completed.contains(today) == true)
        guard let undone = WidgetInbox.toggling(habitID: id, on: today, in: done.snapshot) else { #expect(1 == 2); return }
        #expect(undone.change.completed == false)
        #expect(undone.snapshot.habits[0].timeline.status(on: today, today: today) == .pending)
    }

    @Test func aWidgetCannotInventARecord() {
        let (snap, id) = snapshot(weekdays: .weekdays)
        #expect(WidgetInbox.toggling(habitID: UUID(), on: start, in: snap) == nil)            // unknown habit
        #expect(WidgetInbox.toggling(habitID: id, on: start.adding(5), in: snap) == nil)     // Saturday: a rest day
        #expect(WidgetInbox.toggling(habitID: id, on: start.adding(-1), in: snap) == nil)    // before the plan
        #expect(WidgetInbox.toggling(habitID: id, on: start.adding(120), in: snap) == nil)   // after the plan
    }

    @Test func onlyTheNewestAnswerForADayIsKept() {
        let id = UUID()
        var queue: [PendingCheckIn] = []
        queue = WidgetInbox.adding(PendingCheckIn(habitID: id, day: start, completed: true), to: queue)
        queue = WidgetInbox.adding(PendingCheckIn(habitID: id, day: start, completed: false), to: queue)
        queue = WidgetInbox.adding(PendingCheckIn(habitID: id, day: start.adding(1), completed: true), to: queue)
        #expect(queue.count == 2)
        #expect(queue.first { $0.day == start }?.completed == false)
        #expect(WidgetInbox.applicable(queue, today: start).count == 1)
    }

    @Test func olderSnapshotsWithoutDetailStillDecode() throws {
        let (snap, _) = snapshot()
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any],
              var habits = object["habits"] as? [[String: Any]] else { #expect(1 == 2); return }
        habits[0].removeValue(forKey: "detail")
        object["habits"] = habits
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.habits[0].detail == nil)
        #expect(decoded.habits[0].title == "Read daily")
    }
}
