import Foundation
import ScrapModel
import ScrapTestSupport
import Testing

@testable import ScrapStorage

/// The tenth acceptance criterion, on both full-text engines.
struct IndexSearchTests {
    @Test(arguments: FullTextEngine.allCases)
    func prefixFindsApartmInApartment(engine: FullTextEngine) async throws {
        let (library, index) = try await IndexFixtures.openIndex(engine: engine)
        defer { withExtendedLifetime(library) {} }
        let scrap = IndexFixtures.scrap(body: "A two-bedroom apartment near the park")
        try await index.apply(IndexFixtures.saved(scrap))
        try await index.apply(IndexFixtures.saved(IndexFixtures.scrap(body: "Something else")))

        #expect(await index.engine == engine)
        #expect(try await index.search(SearchQuery("apartm")) == [scrap.id])
        #expect(try await index.search(SearchQuery("two-bedroom apart")) == [scrap.id])
        #expect(try await index.search(SearchQuery("apartmentx")).isEmpty)
    }

    @Test(arguments: FullTextEngine.allCases)
    func searchCoversTitleBodyNoteLabelAndWindow(engine: FullTextEngine) async throws {
        let (library, index) = try await IndexFixtures.openIndex(engine: engine)
        defer { withExtendedLifetime(library) {} }
        let inTitle = IndexFixtures.scrap(title: "Zebra listing")
        let inBody = IndexFixtures.scrap(body: "the yak fence")
        let inNote = IndexFixtures.scrap(note: "ask about the walrus")
        let inLabel = IndexFixtures.scrap(label: "narwhal.com")
        let inWindow = IndexFixtures.scrap(window: "Okapi Realty")
        for scrap in [inTitle, inBody, inNote, inLabel, inWindow] { try await index.apply(IndexFixtures.saved(scrap)) }

        #expect(try await index.search(SearchQuery("zebra")) == [inTitle.id])
        #expect(try await index.search(SearchQuery("yak")) == [inBody.id])
        #expect(try await index.search(SearchQuery("walrus")) == [inNote.id])
        #expect(try await index.search(SearchQuery("narwhal")) == [inLabel.id])
        #expect(try await index.search(SearchQuery("okapi")) == [inWindow.id])
    }

    @Test(arguments: FullTextEngine.allCases)
    func diacriticsAreIgnored(engine: FullTextEngine) async throws {
        let (library, index) = try await IndexFixtures.openIndex(engine: engine)
        defer { withExtendedLifetime(library) {} }
        let accented = IndexFixtures.scrap(body: "Crème brûlée at the café")
        let plain = IndexFixtures.scrap(body: "naive resume")
        try await index.apply(IndexFixtures.saved(accented))
        try await index.apply(IndexFixtures.saved(plain))

        #expect(try await index.search(SearchQuery("creme brulee")) == [accented.id])
        #expect(try await index.search(SearchQuery("CAFE")) == [accented.id])
        #expect(try await index.search(SearchQuery("naïve résumé")) == [plain.id])
    }

    /// Quotes, stars, and FTS operators in what the user types are just text; none of them
    /// fails the query or changes its meaning.
    @Test(arguments: FullTextEngine.allCases)
    func queryOperatorsAreLiteral(engine: FullTextEngine) async throws {
        let (library, index) = try await IndexFixtures.openIndex(engine: engine)
        defer { withExtendedLifetime(library) {} }
        let near = IndexFixtures.scrap(body: "near or not")
        try await index.apply(IndexFixtures.saved(near))
        try await index.apply(IndexFixtures.saved(IndexFixtures.scrap(body: "unrelated words")))

        #expect(try await index.search(SearchQuery("NEAR")) == [near.id])
        #expect(try await index.search(SearchQuery("near OR")) == [near.id])
        #expect(try await index.search(SearchQuery("NOT unrelated")).isEmpty)
        // Punctuation the user types is ignored the same way on both engines.
        for text in ["\"near", "near\"", "near*", "(near", "near)", "-near", "\"near or\""] {
            #expect(try await index.search(SearchQuery(text)) == [near.id], "\(text)")
        }
        for text in ["\"", "*", "AND", "title:near", "", "   ", "!!!"] {
            _ = try await index.search(SearchQuery(text))
        }
    }

    @Test(arguments: FullTextEngine.allCases)
    func searchCanBeLimitedToACollection(engine: FullTextEngine) async throws {
        let (library, index) = try await IndexFixtures.openIndex(engine: engine)
        defer { withExtendedLifetime(library) {} }
        let inbox = IndexFixtures.scrap(body: "apartment")
        let other = IndexFixtures.scrap(body: "apartment")
        try await index.apply(IndexFixtures.saved(inbox))
        try await index.apply(IndexFixtures.saved(other, collection: "Apartment hunt"))

        #expect(try await Set(index.search(SearchQuery("apartment"))) == [inbox.id, other.id])
        #expect(try await index.search(SearchQuery("apartment", in: .inbox)) == [inbox.id])
    }
}
