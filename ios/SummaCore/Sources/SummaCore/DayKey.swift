import Foundation

/// A civil calendar date (year-month-day) with no time or time zone attached.
///
/// Check-ins are stored against the day the user *experienced*, so travelling
/// across time zones or a daylight-saving change never moves a past check-in
/// to a different day. All arithmetic is integer-based on a day ordinal.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(year: Int, month: Int, day: Int) {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        self.ordinal = era * 146097 + doe - 719468
    }

    /// Parses `yyyy-MM-dd`. Returns nil for malformed or impossible dates.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let key = DayKey(year: y, month: m, day: d)
        let c = key.components
        guard c.year == y, c.month == m, c.day == d else { return nil }
        self = key
    }

    /// The civil day that `date` falls on in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public var components: (year: Int, month: Int, day: Int) {
        // Howard Hinnant's civil_from_days.
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    public var string: String {
        let c = components
        func pad(_ v: Int, _ n: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, n - s.count)) + s
        }
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
    }

    public var description: String { string }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday)`.
    public var weekday: Int {
        (((ordinal % 7) + 7 + 4) % 7) + 1
    }

    public func adding(_ days: Int) -> DayKey { DayKey(ordinal: ordinal + days) }

    public func days(until other: DayKey) -> Int { other.ordinal - ordinal }

    /// Noon on this day in the given calendar's time zone. Noon avoids the
    /// missing or repeated hour around daylight-saving transitions.
    public func date(in calendar: Calendar = .current) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = components
        return gregorian.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? Date(timeIntervalSince1970: Double(ordinal) * 86400 + 43200)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.ordinal < rhs.ordinal }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected yyyy-MM-dd, got \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}
