/// Rules the reader and the writer share, so whatever one accepts the other can reproduce.
enum YAMLText {
    /// Characters a double-quoted string writes as `\uXXXX`: C0 and C1 controls, DEL, line and
    /// paragraph separators, the byte-order mark, and the noncharacters U+FFFE and U+FFFF.
    static func needsEscape(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0..<0x20, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF: true
        default: false
        }
    }

    /// A key that can be written unquoted and reads back as itself: no leading indicator or
    /// space, no trailing space or colon, no tabs, line breaks, or characters that need
    /// escaping, no `: ` or ` #` inside, and not a document marker.
    static func isPlainKey(_ key: some Collection<Unicode.Scalar>) -> Bool {
        let scalars = Array(key)
        guard let first = scalars.first, let last = scalars.last,
            !"-?:,[]{}#&*!|>'\"%@` ".unicodeScalars.contains(first),
            last != " ", last != ":",
            !scalars.contains(where: { $0 == "\t" || needsEscape($0) }),
            scalars != Array("...".unicodeScalars), scalars != Array("---".unicodeScalars)
        else { return false }
        return !zip(scalars, scalars.dropFirst()).contains { ($0 == ":" && $1 == " ") || ($0 == " " && $1 == "#") }
    }
}
