import ScrapModel
import ScrapTestSupport
import Testing

struct RankTests {
    /// The acceptance criterion: random insertion points, each new key strictly between its
    /// neighbours, and the whole list strictly ordered at the end.
    @Test func tenThousandRandomInsertionsKeepStrictTotalOrder() throws {
        var random = SeededRandom(seed: 0x5EED_0001)
        var ranks: [Rank] = []
        for step in 0..<10_000 {
            let index = Int.random(in: 0...ranks.count, using: &random)
            let lower = index > 0 ? ranks[index - 1] : nil
            let upper = index < ranks.count ? ranks[index] : nil
            let rank = Rank.between(lower, upper)
            if let lower, !(lower < rank) {
                Issue.record("step \(step): \(rank.rawValue) is not after \(lower.rawValue)")
                return
            }
            if let upper, !(rank < upper) {
                Issue.record("step \(step): \(rank.rawValue) is not before \(upper.rawValue)")
                return
            }
            ranks.insert(rank, at: index)
        }
        #expect(zip(ranks, ranks.dropFirst()).allSatisfy { $0 < $1 })
        #expect(Set(ranks).count == ranks.count)
        // Every generated key is one the parser accepts, so it survives a trip through a file.
        #expect(ranks.allSatisfy { Rank(rawValue: $0.rawValue) == $0 })
    }

    @Test func betweenAdjacentKeysStillFitsAKey() throws {
        var lower = Rank.after(nil)
        var upper = Rank.after(lower)
        for step in 0..<1_000 {
            let middle = Rank.between(lower, upper)
            try #require(lower < middle && middle < upper, "step \(step)")
            // Alternate which side moves, so keys must keep fitting into ever-smaller gaps.
            if step.isMultiple(of: 2) { lower = middle } else { upper = middle }
        }
    }

    @Test func afterAndBeforeHandleNil() {
        let first = Rank.between(nil, nil)
        #expect(Rank.after(nil) == first)
        #expect(Rank.before(nil) == first)
        #expect(first < Rank.after(first))
        #expect(Rank.before(first) < first)
    }

    @Test func appendsKeepKeysShort() throws {
        var rank = Rank.after(nil)
        for _ in 0..<10_000 {
            let next = Rank.after(rank)
            try #require(rank < next)
            rank = next
        }
        #expect(rank.rawValue.count < 8)
    }

    @Test func prependsKeepKeysShort() throws {
        var rank = Rank.before(nil)
        for _ in 0..<10_000 {
            let next = Rank.before(rank)
            try #require(next < rank)
            rank = next
        }
        #expect(rank.rawValue.count < 8)
    }

    /// Two scraps can share a rank (a file copied in Finder). There's no key strictly between
    /// equal keys, so `between` places the new key just after both, still below the next
    /// integer, so it doesn't tie with a card ranked there.
    @Test func equalNeighboursGiveKeyAfterBoth() throws {
        let rank = try #require(Rank(rawValue: "a3"))
        let next = try #require(Rank(rawValue: "a4"))
        let result = Rank.between(rank, rank)
        #expect(rank < result)
        #expect(result < next)
    }

    @Test func invertedNeighboursGiveKeyAfterLower() throws {
        let low = try #require(Rank(rawValue: "a3"))
        let high = try #require(Rank(rawValue: "a7"))
        let result = Rank.between(high, low)
        #expect(high < result)
        #expect(result < Rank(rawValue: "a8")!)
    }

    /// Each place the integer part changes head letter, in both directions.
    @Test(arguments: [
        ("Zz", "a0"),  // last negative integer to the first positive one
        ("az", "b00"),  // one digit to two
        ("Yzz", "Z0"),  // two digits to one, below zero
        ("a0V", "a1"),  // a fraction steps to the next integer
    ])
    func headLetterTransitions(lower: String, upper: String) throws {
        let low = try #require(Rank(rawValue: lower))
        let high = try #require(Rank(rawValue: upper))
        #expect(Rank.after(low) == high)
        if !lower.contains("V") {
            #expect(Rank.before(high) == low)
        }
    }

    @Test func largestIntegerFallsBackToFraction() throws {
        let largest = try #require(Rank(rawValue: "z" + String(repeating: "z", count: 26)))
        let next = Rank.after(largest)
        #expect(largest < next)
        #expect(next.rawValue.hasPrefix(largest.rawValue))
    }

    /// Only the exact lowest key is reserved, so keys above it can still be prepended to.
    @Test func keysBelowTheLowestIntegerUseFractions() throws {
        let zeros = String(repeating: "0", count: 25)
        let lowestUsable = try #require(Rank(rawValue: "A" + zeros + "1"))
        let below = Rank.before(lowestUsable)
        #expect(below.rawValue == "A" + zeros + "0V")
        let further = Rank.before(below)
        #expect(further < below)
        #expect(Rank(rawValue: further.rawValue) == further)
    }

    @Test(arguments: [
        "a0", "a3", "az", "Zz", "b00", "a0V", "a3x1", "zzzzzzzzzzzzzzzzzzzzzzzzzzz",
        "A00000000000000000000000000V",
    ])
    func acceptsValidKeys(raw: String) {
        #expect(Rank(rawValue: raw)?.rawValue == raw)
    }

    @Test(arguments: [
        "",  // empty
        "a",  // shorter than its integer part
        "b0",  // "b" needs two digits after it
        "0a",  // must start with a letter
        "a-",  // not a base-62 digit
        "a3 ",  // trailing space
        "a\u{E9}",  // non-ASCII
        "a30",  // fraction ends in zero, leaving no room below it
        "A00000000000000000000000000",  // the smallest integer is reserved
    ])
    func rejectsInvalidKeys(raw: String) {
        #expect(Rank(rawValue: raw) == nil)
    }

    @Test func ordersByBytes() throws {
        let keys = try ["Zz", "a0", "a0V", "a1", "az", "b00"].map { try #require(Rank(rawValue: $0)) }
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 })
    }
}
