import Foundation

/// ISO 8601 timestamps as frontmatter stores them: written in UTC to the whole second
/// (`2026-09-29T14:02:11Z`); read with or without fractional seconds, as `Z` or a `±hh:mm`
/// offset.
enum UTCTimestamp {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func format(_ date: Date) -> String {
        let whole = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        return pad(parts.year, 4) + "-" + pad(parts.month, 2) + "-" + pad(parts.day, 2) + "T"
            + pad(parts.hour, 2) + ":" + pad(parts.minute, 2) + ":" + pad(parts.second, 2) + "Z"
    }

    static func parse(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[range] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        func byte(_ index: Int, is expected: Character) -> Bool {
            index < bytes.count && bytes[index] == expected.asciiValue
        }
        guard let year = number(0..<4), byte(4, is: "-"), let month = number(5..<7), byte(7, is: "-"),
            let day = number(8..<10), byte(10, is: "T"), let hour = number(11..<13), byte(13, is: ":"),
            let minute = number(14..<16), byte(16, is: ":"), let second = number(17..<19),
            (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60
        else { return nil }

        var index = 19
        var fraction = 0.0
        if byte(index, is: ".") {
            let start = index + 1
            index = start
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                index += 1
            }
            guard index > start, let value = Double("0." + String(decoding: bytes[start..<index], as: UTF8.self))
            else { return nil }
            fraction = value
        }

        var offset = 0
        if byte(index, is: "Z") {
            index += 1
        } else if byte(index, is: "+") || byte(index, is: "-") {
            guard let hours = number(index + 1..<index + 3), byte(index + 3, is: ":"),
                let minutes = number(index + 4..<index + 6), hours < 24, minutes < 60
            else { return nil }
            offset = (hours * 3600 + minutes * 60) * (byte(index, is: "-") ? -1 : 1)
            index += 6
        } else {
            return nil
        }
        guard index == bytes.count else { return nil }

        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts),
            calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month
        else { return nil }
        return date.addingTimeInterval(fraction - Double(offset))
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let digits = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
