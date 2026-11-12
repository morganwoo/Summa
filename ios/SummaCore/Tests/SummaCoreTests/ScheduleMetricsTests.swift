import Foundation
import Testing
@testable import SummaCore

// Rules under test are documented on `HabitMetrics` and shown in the app.

private func day(_ s: String) -> DayKey { DayKey(s)! }

/// 2026-11-02 is a Monday.
private let monday = day("2026-11-02")

private func timeline(weekdays: WeekdaySet = .everyDay, completed: [String] = [], start: DayKey = monday) -> HabitTimeline {
    HabitTimeline(planStart: start, rules: [ScheduleRule(effectiveFrom: start, weekdays: weekdays)],
                  completed: Set(completed.map { day($0) }))
}

@Suite struct DayKeyTests {
    @Test func roundTripsThroughStrings() {
        for s in ["1970-01-01", "2024-02-29", "2026-11-11", "1999-12-31", "2100-03-01"] {
            #expect(DayKey(s)?.string == s)
        }
        #expect(DayKey("1970-01-01")?.ordinal == 0)
    }

    @Test func rejectsImpossibleDates() {
        #expect(DayKey("2026-02-30") == nil)
        #expect(DayKey("2025-02-29") == nil)
        #expect(DayKey("2026-13-01") == nil)
        #expect(DayKey("20261101") == nil)
        #expect(DayKey("2026-1-1") == nil)
    }

    @Test func weekdayMatchesCalendar() {
        #expect(day("1970-01-01").weekday == 5) // Thursday
        #expect(monday.weekday == 2)
        #expect(day("2026-11-08").weekday == 1) // Sunday
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for offset in 0..<800 {
            let key = day("2025-01-01").adding(offset)
            #expect(utc.component(.weekday, from: key.date(in: utc)) == key.weekday)
        }
    }

    @Test func addingCrossesMonthsAndLeapYears() {
        #expect(day("2024-02-28").adding(1).string == "2024-02-29")
        #expect(day("2024-02-28").adding(2).string == "2024-03-01")
        #expect(day("2026-12-31").adding(1).string == "2027-01-01")
        #expect(day("2026-11-02").days(until: day("2027-01-30")) == 89)
    }

    @Test func sameInstantIsDifferentDaysInDifferentZones() {
        // 2026-11-11 06:30 UTC is still Nov 10 in Vancouver and already Nov 11 in Tokyo.
        let instant = Date(timeIntervalSince1970: 1_794_378_600)
        var vancouver = Calendar(identifier: .gregorian)
        vancouver.timeZone = TimeZone(identifier: "America/Vancouver")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(DayKey(date: instant, calendar: vancouver).string == "2026-11-10")
        #expect(DayKey(date: instant, calendar: tokyo).string == "2026-11-11")
    }

    @Test func daylightSavingDaysAreStillOneDay() {
        // Historical transitions, so later changes to time-zone law cannot move them:
        // Los Angeles sprang forward on 2025-03-09 (23 hours) and fell back on 2025-11-02 (25 hours).
        var zone = Calendar(identifier: .gregorian)
        zone.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for s in ["2025-03-09", "2025-11-02"] {
            let key = day(s)
            let start = zone.startOfDay(for: key.date(in: zone))
            #expect(DayKey(date: start, calendar: zone) == key)
            #expect(DayKey(date: start.addingTimeInterval(-1), calendar: zone) == key.adding(-1))
            let nextStart = zone.startOfDay(for: key.adding(1).date(in: zone))
            #expect(DayKey(date: nextStart.addingTimeInterval(-1), calendar: zone) == key)
            #expect(DayKey(date: nextStart, calendar: zone) == key.adding(1))
        }
        let springForward = zone.startOfDay(for: day("2025-03-09").date(in: zone))
        // 23 hours after midnight on the short day is already the next day…
        #expect(DayKey(date: springForward.addingTimeInterval(23 * 3600), calendar: zone).string == "2025-03-10")
        let fallBack = zone.startOfDay(for: day("2025-11-02").date(in: zone))
        // …and 25 hours minus a second after midnight on the long day is still the same day.
        #expect(DayKey(date: fallBack.addingTimeInterval(25 * 3600 - 1), calendar: zone).string == "2025-11-02")
    }

    @Test func aCheckInKeepsItsDayAfterTravel() {
        // The stored key is a civil date, so re-reading it in another zone cannot move it.
        let key = day("2026-11-10")
        let data = try! JSONEncoder().encode([key])
        let decoded = try! JSONDecoder().decode([DayKey].self, from: data)
        #expect(decoded == [key])
        #expect(String(data: data, encoding: .utf8) == "[\"2026-11-10\"]")
    }
}

@Suite struct ScheduleTests {
    @Test func planCoversExactlyNinetyDays() {
        let t = timeline()
        #expect(t.days.count == 90)
        #expect(t.planEnd.string == "2027-01-30")
        #expect(t.dayNumber(today: monday) == 1)
        #expect(t.dayNumber(today: monday.adding(23)) == 24)
        #expect(t.dayNumber(today: monday.adding(500)) == 90)
        #expect(t.dayNumber(today: monday.adding(-1)) == nil)
    }

    @Test func statusesForEachKindOfDay() {
        let t = timeline(weekdays: .weekdays, completed: ["2026-11-02"])
        let today = day("2026-11-04") // Wednesday
        #expect(t.status(on: day("2026-11-02"), today: today) == .completed)
        #expect(t.status(on: day("2026-11-03"), today: today) == .missed)
        #expect(t.status(on: today, today: today) == .pending)
        #expect(t.status(on: day("2026-11-05"), today: today) == .upcoming)
        #expect(t.status(on: day("2026-11-07"), today: today) == .unscheduled) // Saturday
        #expect(t.status(on: day("2026-11-01"), today: today) == .unscheduled) // before the plan
    }

    @Test func changingAScheduleKeepsPastHistory() {
        // Weekdays for week one, then Mon/Wed/Fri from the second Monday.
        var t = timeline(weekdays: .weekdays, completed: ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"])
        t.rules.append(ScheduleRule(effectiveFrom: day("2026-11-09"), weekdays: WeekdaySet(weekdays: [2, 4, 6])))
        let today = day("2026-11-11")
        #expect(t.isScheduled(day("2026-11-03"))) // the old Tuesday still counted
        #expect(!t.isScheduled(day("2026-11-10"))) // the new Tuesday is a rest day
        let m = HabitMetrics.compute(t, today: today)
        #expect(m.scheduledCount == 7) // 5 + Mon + Wed
        #expect(m.completedCount == 5)
        #expect(t.status(on: day("2026-11-09"), today: today) == .missed)
    }

    @Test func habitsAddedMidPlanAreNotMissedBeforeTheyExisted() {
        var t = timeline()
        t.habitStart = monday.adding(10)
        let today = monday.adding(12)
        #expect(t.status(on: monday.adding(3), today: today) == .unscheduled)
        #expect(t.status(on: monday.adding(10), today: today) == .missed)
        #expect(HabitMetrics.compute(t, today: today).scheduledCount == 3)
    }

    @Test func archivedHabitsStopBeingScheduled() {
        var t = timeline(completed: ["2026-11-02"])
        t.archivedOn = day("2026-11-04")
        let today = day("2026-11-10")
        #expect(t.status(on: day("2026-11-03"), today: today) == .missed)
        #expect(t.status(on: day("2026-11-04"), today: today) == .unscheduled)
        #expect(HabitMetrics.compute(t, today: today).scheduledCount == 2)
    }

    @Test func nextScheduledDaySkipsRestDays() {
        let t = timeline(weekdays: .weekdays)
        #expect(t.nextScheduledDay(after: day("2026-11-06"))?.string == "2026-11-09")
        #expect(t.nextScheduledDay(after: t.planEnd) == nil)
    }
}

@Suite struct MetricsTests {
    @Test func emptyTimelineBeforeAnythingIsDue() {
        let t = timeline(weekdays: WeekdaySet(weekdays: [4])) // Wednesdays only
        let m = HabitMetrics.compute(t, today: monday)
        #expect(m.scheduledCount == 0)
        #expect(m.completion == nil)
        #expect(m.currentStreak == 0)
        #expect(m.todayStatus == .unscheduled)
    }

    @Test func pendingTodayDoesNotBreakTheStreak() {
        let t = timeline(completed: ["2026-11-02", "2026-11-03", "2026-11-04"])
        let today = day("2026-11-05")
        let m = HabitMetrics.compute(t, today: today)
        #expect(m.todayStatus == .pending)
        #expect(m.currentStreak == 3)
        #expect(m.longestStreak == 3)
        // …but today is already in the completion denominator.
        #expect(m.scheduledCount == 4)
        #expect(m.completedCount == 3)
        #expect(m.completionPercent == 75)
    }

    @Test func completingTodayExtendsTheStreak() {
        var t = timeline(completed: ["2026-11-02", "2026-11-03", "2026-11-04"])
        let today = day("2026-11-05")
        t.completed = CheckInLedger.marking(today, in: t.completed)
        let m = HabitMetrics.compute(t, today: today)
        #expect(m.currentStreak == 4)
        #expect(m.completionPercent == 100)
        #expect(m.todayStatus == .completed)
    }

    @Test func onceTheDayEndsAnUnfinishedOccurrenceBreaksTheStreak() {
        let t = timeline(completed: ["2026-11-02", "2026-11-03", "2026-11-04"])
        let m = HabitMetrics.compute(t, today: day("2026-11-06"))
        #expect(m.currentStreak == 0)
        #expect(m.longestStreak == 3)
    }

    @Test func restDaysPreserveTheStreak() {
        // Weekdays only: Friday then Monday are consecutive occurrences.
        let t = timeline(weekdays: .weekdays, completed: ["2026-11-05", "2026-11-06", "2026-11-09"])
        let sunday = HabitMetrics.compute(t, today: day("2026-11-08"))
        #expect(sunday.currentStreak == 2)
        #expect(sunday.todayStatus == .unscheduled)
        let mondayNext = HabitMetrics.compute(t, today: day("2026-11-09"))
        #expect(mondayNext.currentStreak == 3)
    }

    @Test func aMissedDayStaysVisibleAndResetsOnlyTheCurrentRun() {
        let t = timeline(completed: ["2026-11-02", "2026-11-03", "2026-11-05", "2026-11-06"])
        let m = HabitMetrics.compute(t, today: day("2026-11-06"))
        #expect(t.status(on: day("2026-11-04"), today: day("2026-11-06")) == .missed)
        #expect(m.currentStreak == 2)
        #expect(m.longestStreak == 2)
        #expect(m.completedCount == 4)
        #expect(m.scheduledCount == 5)
        #expect(m.completionPercent == 80)
    }

    @Test func checkInsOnRestDaysDoNotInflateCompletion() {
        let t = timeline(weekdays: .weekdays, completed: ["2026-11-06", "2026-11-07"]) // Fri + bonus Sat
        let m = HabitMetrics.compute(t, today: day("2026-11-08"))
        #expect(m.completedCount == 1)
        #expect(m.scheduledCount == 5)
        #expect(m.currentStreak == 1)
        #expect(t.status(on: day("2026-11-07"), today: day("2026-11-08")) == .completed)
    }

    @Test func completionStopsAtTheEndOfTheRangeOrTodayWhicheverIsFirst() {
        let t = timeline(completed: ["2026-11-02", "2026-11-03"])
        let today = day("2026-11-11")
        let firstWeek = HabitMetrics.compute(t, today: today, range: monday...monday.adding(6))
        #expect(firstWeek.scheduledCount == 7)
        #expect(firstWeek.completedCount == 2)
        #expect(firstWeek.measuredRange == monday...monday.adding(6))
        let november = HabitMetrics.compute(t, today: today, range: day("2026-11-01")...day("2026-11-30"))
        #expect(november.scheduledCount == 10) // Nov 2 through Nov 11
        #expect(november.measuredRange == monday...today)
        let future = HabitMetrics.compute(t, today: today, range: day("2026-12-01")...day("2026-12-31"))
        #expect(future.scheduledCount == 0)
        #expect(future.completion == nil)
        #expect(future.measuredRange == nil)
    }

    @Test func nothingCountsAfterDayNinety() {
        var t = timeline()
        t.completed = Set(t.days)
        let m = HabitMetrics.compute(t, today: t.planEnd.adding(40))
        #expect(m.scheduledCount == 90)
        #expect(m.completedCount == 90)
        #expect(m.currentStreak == 90)
        #expect(m.todayStatus == .unscheduled)
    }

    @Test func duplicateWritesAreIdempotent() {
        let id = UUID()
        let today = day("2026-11-02")
        #expect(CheckInLedger.key(habitID: id, day: today) == CheckInLedger.key(habitID: id, day: day("2026-11-02")))
        #expect(CheckInLedger.key(habitID: id, day: today) != CheckInLedger.key(habitID: UUID(), day: today))
        var completed: Set<DayKey> = []
        completed = CheckInLedger.marking(today, in: completed)
        completed = CheckInLedger.marking(today, in: completed)
        #expect(completed.count == 1)
        let once = HabitMetrics.compute(timeline(completed: ["2026-11-02"]), today: today)
        var t = timeline()
        t.completed = completed
        #expect(HabitMetrics.compute(t, today: today) == once)
        completed = CheckInLedger.clearing(today, in: completed)
        completed = CheckInLedger.clearing(today, in: completed)
        #expect(completed.isEmpty)
    }

    @Test func weekIsMondayFirstAndContainsToday() {
        let week = WidgetSnapshot.week(containing: day("2026-11-08")) // Sunday
        #expect(week.first?.string == "2026-11-02")
        #expect(week.last?.string == "2026-11-08")
        #expect(WidgetSnapshot.week(containing: monday).first == monday)
    }
}
