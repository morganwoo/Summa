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
        let plan = try PlanDraft(objective: "  Read more.  ", habits: [h, habit("Train")]).validated()
        #expect(plan.objective == "Read more.")
        #expect(plan.habits[0].title == "Read daily")
        #expect(plan.habits[0].weekdays == [2, 4, 6])
        #expect(HabitPalette.isValidHex(plan.habits[0].colorHex))
        #expect(plan.phases.map { $0.title } == ["Find your footing", "Settle into rhythm", "Make it yours"])
    }

    @Test func rejectsTooFewOrTooManyHabits() {
        for count in [0, 1, 5] {
            let plan = PlanDraft(objective: "x", habits: (0..<count).map { habit("H\($0)") })
            var caught: PlanValidationError?
            do { _ = try plan.validated() } catch { caught = error as? PlanValidationError }
            #expect(caught == .habitCount(count))
        }
    }

    @Test func rejectsBadFields() {
        func error(_ mutate: (inout PlanDraft) -> Void) -> PlanValidationError? {
            var plan = PlanDraft(objective: "Read more", habits: [habit(), habit("Train")])
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
          {"title":"Morning light","action":"Ten minutes outside after waking","minimumVersion":"Open the curtains","weekdays":[2,3,4,5,6]}
        ],"phases":[
          {"title":"Find your footing","startDay":1,"endDay":21,"focus":"a"},
          {"title":"Settle into rhythm","startDay":22,"endDay":66,"focus":"b"},
          {"title":"Make it yours","startDay":67,"endDay":90,"focus":"c"}]}
        """
        let plan = try JSONDecoder().decode(PlanDraft.self, from: Data(json.utf8)).validated()
        #expect(plan.habits.count == 2)
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

@Suite struct StarterPlanTests {
    @Test func alwaysProducesAValidPlan() throws {
        let focusSets: [[String]] = [[], ["Reading"], ["Reflection"], ["Focus", "Movement", "Reading", "Sleep routine", "Reflection"], ["Learn the cello"]]
        for focus in focusSets {
            for size in ["", "Tiny — almost too easy", "Ambitious — I have room for it"] {
                var a = OnboardingAnswers()
                a.set(.focus, focus)
                a.set(.startSize, text: size)
                a.set(.minutes, text: "45 minutes or more")
                let plan = try StarterPlanBuilder.build(from: a).validated()
                #expect((2...4).contains(plan.habits.count))
                #expect(Set(plan.habits.map { $0.colorHex }).count == plan.habits.count)
                #expect(plan.source == "starter")
            }
        }
    }

    @Test func respectsDaysTimeAndObjective() throws {
        var a = OnboardingAnswers()
        a.set(.focus, ["Reading", "Movement"])
        a.set(.days, ["2", "4", "6"])
        a.set(.timeOfDay, text: "Morning")
        a.set(.minutes, text: "20 minutes")
        a.set(.objective, text: "Finish four books")
        let plan = try StarterPlanBuilder.build(from: a).validated()
        #expect(plan.objective == "Finish four books")
        #expect(plan.habits.allSatisfy { $0.weekdays == [2, 4, 6] })
        #expect(plan.habits[0].reminder == ReminderDraft(hour: 7, minute: 30))
        #expect(plan.habits[0].title == "Read daily")
    }
}
