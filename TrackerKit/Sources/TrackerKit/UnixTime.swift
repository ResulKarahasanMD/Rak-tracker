/// Deterministic, locale/timezone-independent time formatting for exports.
public enum UnixTime {
    /// Renders a unix timestamp as `YYYY-MM-DDTHH:MM:SSZ` (UTC).
    public static func iso8601String(_ timestamp: Int32) -> String {
        let total = Int64(timestamp)
        var days = total / 86_400
        var secondsOfDay = total % 86_400
        if secondsOfDay < 0 {
            secondsOfDay += 86_400
            days -= 1
        }
        let (year, month, day) = civilFromDays(days)
        let hour = secondsOfDay / 3_600
        let minute = (secondsOfDay % 3_600) / 60
        let second = secondsOfDay % 60
        return "\(pad(year, 4))-\(pad(Int64(month), 2))-\(pad(Int64(day), 2))"
            + "T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2))Z"
    }

    /// Days-to-civil-date conversion (Howard Hinnant's algorithm),
    /// exact for the proleptic Gregorian calendar.
    private static func civilFromDays(_ daysSinceEpoch: Int64) -> (year: Int64, month: Int, day: Int) {
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (month <= 2 ? year + 1 : year, Int(month), Int(day))
    }

    private static func pad(_ value: Int64, _ width: Int) -> String {
        var text = String(value)
        while text.count < width { text = "0" + text }
        return text
    }
}
