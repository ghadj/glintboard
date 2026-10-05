import Foundation
import ScrapModel
import Testing

struct FingerprintTests {
    // Known SHA-256 digests (FIPS 180-2 test vector for "abc", and the empty input).
    private static let sha256OfABC = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private static let sha256OfEmpty = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    @Test func textDifferingOnlyInCompositionMatches() {
        let precomposed = "caf\u{E9} cr\u{E8}me"  // é and è as single code points
        let decomposed = "cafe\u{301} cre\u{300}me"  // e plus combining accents
        #expect(Array(precomposed.utf8) != Array(decomposed.utf8))
        #expect(Fingerprint.text(precomposed) == Fingerprint.text(decomposed))
    }

    @Test(arguments: [
        "a   b",
        "  a b  ",
        "a\tb",
        "a\n\nb\n",
        "a\r\nb",
        "a\u{A0}b",  // no-break space
        "a\u{2028}b",  // line separator
        "\u{3000}a \t b",  // ideographic space
    ])
    func textDifferingOnlyInWhitespaceMatches(variant: String) {
        #expect(Fingerprint.text(variant) == Fingerprint.text("a b"))
    }

    @Test func whitespaceIsCollapsedNotRemoved() {
        #expect(Fingerprint.text("a b") != Fingerprint.text("ab"))
    }

    /// Whitespace means the Unicode White_Space property, which doesn't include the
    /// zero-width space, so U+200B is kept as content.
    @Test func zeroWidthSpaceIsNotWhitespace() {
        #expect(Fingerprint.text("a\u{200B}b") != Fingerprint.text("a b"))
        #expect(Fingerprint.text("a\u{200B}b") != Fingerprint.text("ab"))
    }

    @Test func differentTextDiffers() {
        #expect(Fingerprint.text("abc") != Fingerprint.text("abd"))
        #expect(Fingerprint.text("abc") != Fingerprint.text("ABC"))
    }

    @Test func textHashesNormalizedUTF8() {
        #expect(Fingerprint.text("  abc \n").rawValue == Self.sha256OfABC)
        #expect(Fingerprint.text(" \n\t ").rawValue == Self.sha256OfEmpty)
    }

    @Test func imageFingerprintHashesBytes() {
        #expect(Fingerprint.data(Data("abc".utf8)).rawValue == Self.sha256OfABC)
        #expect(Fingerprint.data(Data()).rawValue == Self.sha256OfEmpty)
    }

    @Test func imageBytesAreNotNormalized() {
        #expect(Fingerprint.data(Data(" abc".utf8)) != Fingerprint.data(Data("abc".utf8)))
    }

    @Test func formatIsPrefixedLowercaseHex() {
        let raw = Fingerprint.data(Data([0xFF, 0x00, 0xAB])).rawValue
        #expect(raw.hasPrefix("sha256:"))
        let hex = raw.dropFirst("sha256:".count)
        #expect(hex.count == 64)
        let lowercaseHex = hex.allSatisfy { "0123456789abcdef".contains($0) }
        #expect(lowercaseHex)
    }
}
