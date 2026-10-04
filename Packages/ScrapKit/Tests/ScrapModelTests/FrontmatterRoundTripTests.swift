import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

struct FrontmatterRoundTripTests {
    /// The first acceptance criterion: 1,000 generated scraps read back unchanged, and after one
    /// write the text is a fixed point of read-then-write.
    @Test func thousandGeneratedScrapsRoundTripByteIdentically() throws {
        var generator = ScrapGenerator(seed: 0x5C2A_9001)
        for index in 0..<1_000 {
            let scrap = generator.scrap()
            let once = FrontmatterCodec.encode(scrap)
            let decoded: Scrap
            do {
                decoded = try FrontmatterCodec.decode(once)
            } catch {
                Issue.record("scrap \(index): \(error)\n\(once)")
                return
            }
            if decoded != scrap {
                Issue.record("scrap \(index) changed on read-back:\n\(once)")
                return
            }
            let twice = FrontmatterCodec.encode(decoded)
            if Array(twice.utf8) != Array(once.utf8) {
                Issue.record("scrap \(index) isn't a fixed point:\n\(once)\n---- became ----\n\(twice)")
                return
            }
        }
    }

    /// A file written by another tool is rewritten once into the canonical form (quoted strings,
    /// block lists, fixed key order) and is stable after that.
    @Test func normalizationPassRewritesPlainScalarsAsQuoted() throws {
        let original = try Fixtures.text("obsidian-edited.md")
        let once = FrontmatterCodec.encode(try FrontmatterCodec.decode(original))
        #expect(
            once == """
                ---
                schema: 1
                id: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"
                kind: "text"
                title: "2BR on Elm St"
                pinned: false
                board: "a3"
                created: 2026-09-29T14:02:11Z
                updated: 2026-09-29T14:02:11Z
                reference:
                  provider: "safari"
                  app: "com.apple.Safari"
                  window: "2BR Apartment - Zillow's page"
                  locator: "https://www.zillow.com/homedetails/4471"
                  label: "zillow.com"
                  fingerprint: "sha256:9b2f"
                tags:
                  - "apartment"
                  - "follow-up"
                status: "shortlisted"
                aliases:
                  - "Elm St"
                  - "2BR"
                rating: 4.5
                due: 2026-10-15
                reviewed: true
                empty:
                ---
                2BR, 850 sq ft

                """)
        #expect(FrontmatterCodec.encode(try FrontmatterCodec.decode(once)) == once)
    }
}
