import Testing

@testable import ScrapModel

struct ScrapSchemaTests {
    @Test func currentSchemaIsOne() {
        #expect(ScrapSchema.current == 1)
    }
}
