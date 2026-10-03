/// A fractional board sort key, written as `board` in frontmatter. A key can always be made
/// before, after, or between existing keys, so a reorder rewrites only the moved scrap's file.
///
/// Keys are base-62 strings (`0-9A-Za-z`, which sort in ASCII order) compared by their bytes.
/// Each key is an integer part followed by an optional fraction:
/// - The integer part's first letter gives its length: `a` is followed by 1 digit, `b` by 2,
///   up to `z` by 26; `Z` is followed by 1 digit, `Y` by 2, down to `A` by 26 (those sort
///   below the `a` keys). Appends and prepends step the integer, so their keys stay short:
///   10,000 appends from `a0` end at four characters.
/// - The fraction holds keys made between two neighbours. It never ends in `0`, so there's
///   always room for another key below it.
///
/// The exact key `A` followed by 26 zeros is reserved, so there's always room below the lowest key.
public struct Rank: Hashable, Sendable {
    public let rawValue: String

    /// Accepts only well-formed keys, such as the ones this type generates.
    public init?(rawValue: String) {
        guard Self.isValid(Array(rawValue.utf8)) else { return nil }
        self.rawValue = rawValue
    }

    private init(bytes: [UInt8]) {
        rawValue = String(decoding: bytes, as: UTF8.self)
    }

    /// A key strictly between `lower` and `upper`; nil means no bound on that side.
    ///
    /// If `lower` isn't below `upper` (two scraps can share a key after a file is copied in
    /// Finder), there's no key between them. The result is then the smallest step after
    /// `lower` (`a3` gives `a3V`, not `a4`), so it doesn't tie with the card after the pair.
    public static func between(_ lower: Rank?, _ upper: Rank?) -> Rank {
        let a = lower.map { Array($0.rawValue.utf8) }
        let b = upper.map { Array($0.rawValue.utf8) }
        if let a, let b, !a.lexicographicallyPrecedes(b) {
            let (integer, fraction) = split(a)
            return Rank(bytes: integer + midpoint(fraction, nil))
        }
        return Rank(bytes: key(between: a, b))
    }

    /// A key after `lower`, or the first key if `lower` is nil.
    public static func after(_ lower: Rank?) -> Rank { between(lower, nil) }

    /// A key before `upper`, or the first key if `upper` is nil.
    public static func before(_ upper: Rank?) -> Rank { between(nil, upper) }
}

extension Rank: Comparable {
    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}

// MARK: - Key arithmetic

extension Rank {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    private static let zero = UInt8(ascii: "0")
    private static let lastDigit = UInt8(ascii: "z")
    private static let smallestInteger = [UInt8(ascii: "A")] + Array(repeating: zero, count: 26)

    private static func value(of byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): Int(byte - UInt8(ascii: "A")) + 10
        case UInt8(ascii: "a")...UInt8(ascii: "z"): Int(byte - UInt8(ascii: "a")) + 36
        default: nil
        }
    }

    /// Length of the integer part, head letter included, or nil if `head` isn't a letter.
    private static func integerLength(head: UInt8) -> Int? {
        switch head {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): Int(head - UInt8(ascii: "a")) + 2
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): Int(UInt8(ascii: "Z") - head) + 2
        default: nil
        }
    }

    private static func isValid(_ key: [UInt8]) -> Bool {
        guard let head = key.first, let length = integerLength(head: head), key.count >= length,
            key.allSatisfy({ value(of: $0) != nil })
        else { return false }
        if key == smallestInteger { return false }
        return key.count == length || key.last != zero
    }

    /// Splits a valid key into its integer part and fraction.
    private static func split(_ key: [UInt8]) -> (integer: [UInt8], fraction: [UInt8]) {
        let length = key.first.flatMap { integerLength(head: $0) } ?? key.count
        return (Array(key.prefix(length)), Array(key.dropFirst(length)))
    }

    private static func key(between a: [UInt8]?, _ b: [UInt8]?) -> [UInt8] {
        switch (a, b) {
        case (nil, nil):
            return [UInt8(ascii: "a"), zero]
        case (nil, let b?):
            let (integer, fraction) = split(b)
            // Below the reserved integer only fractions are left.
            if integer == smallestInteger { return integer + midpoint(nil, fraction) }
            if !fraction.isEmpty { return integer }
            // `integer` isn't the smallest, so it always has a predecessor. When that's the
            // reserved key itself, use a fraction above it instead.
            guard let previous = decrement(integer), previous != smallestInteger else {
                return smallestInteger + midpoint(nil, nil)
            }
            return previous
        case (let a?, nil):
            let (integer, fraction) = split(a)
            return increment(integer) ?? integer + midpoint(fraction, nil)
        case (let a?, let b?):
            let (integerA, fractionA) = split(a)
            let (integerB, fractionB) = split(b)
            if integerA == integerB { return integerA + midpoint(fractionA, fractionB) }
            if let next = increment(integerA), next.lexicographicallyPrecedes(b) { return next }
            return integerA + midpoint(fractionA, nil)
        }
    }

    /// A fraction strictly between `a` and `b`, read as base-62 digits after the point; nil `a`
    /// is 0 and nil `b` is 1. Neither input ends in `0`, and neither does the result.
    private static func midpoint(_ a: [UInt8]?, _ b: [UInt8]?) -> [UInt8] {
        let a = a ?? []
        if let b, !b.isEmpty {
            // Keep the digits the two share (a is padded with zeros), then split what's left.
            var shared = 0
            while shared < b.count, (shared < a.count ? a[shared] : zero) == b[shared] {
                shared += 1
            }
            if shared > 0 {
                return Array(b.prefix(shared))
                    + midpoint(Array(a.dropFirst(shared)), Array(b.dropFirst(shared)))
            }
        }
        let upper = b.flatMap { $0.isEmpty ? nil : $0 }
        let digitA = a.first.flatMap { value(of: $0) } ?? 0
        let digitB = upper?.first.flatMap { value(of: $0) } ?? digits.count
        if digitB - digitA > 1 {
            return [digits[(digitA + digitB + 1) / 2]]
        }
        // Adjacent first digits: b's first digit alone is between them when b has more digits;
        // otherwise keep a's first digit and find a point above the rest of a.
        if let upper, upper.count > 1 {
            return [upper[0]]
        }
        return [digits[digitA]] + midpoint(Array(a.dropFirst()), nil)
    }

    /// The next integer part, or nil after the largest (`z` followed by 26 `z`s).
    private static func increment(_ integer: [UInt8]) -> [UInt8]? {
        guard let head = integer.first else { return nil }
        var body = Array(integer.dropFirst())
        for index in body.indices.reversed() {
            let next = (value(of: body[index]) ?? 0) + 1
            if next < digits.count {
                body[index] = digits[next]
                return [head] + body
            }
            body[index] = zero
        }
        // Every digit carried: move to the next head letter, one digit longer or shorter.
        switch head {
        case UInt8(ascii: "Z"): return [UInt8(ascii: "a"), zero]
        case UInt8(ascii: "z"): return nil
        default:
            let nextHead = head + 1
            if nextHead > UInt8(ascii: "a") { body.append(zero) } else { body.removeLast() }
            return [nextHead] + body
        }
    }

    /// The previous integer part, or nil before the smallest.
    private static func decrement(_ integer: [UInt8]) -> [UInt8]? {
        guard let head = integer.first else { return nil }
        var body = Array(integer.dropFirst())
        for index in body.indices.reversed() {
            let previous = (value(of: body[index]) ?? 0) - 1
            if previous >= 0 {
                body[index] = digits[previous]
                return [head] + body
            }
            body[index] = lastDigit
        }
        switch head {
        case UInt8(ascii: "a"): return [UInt8(ascii: "Z"), lastDigit]
        case UInt8(ascii: "A"): return nil
        default:
            let previousHead = head - 1
            if previousHead < UInt8(ascii: "Z") { body.append(lastDigit) } else { body.removeLast() }
            return [previousHead] + body
        }
    }
}
