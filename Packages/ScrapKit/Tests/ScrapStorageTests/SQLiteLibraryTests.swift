import Testing

@testable import ScrapStorage

struct SQLiteLibraryTests {
    @Test func linksSystemSQLite3() {
        #expect(SQLiteLibrary.version.hasPrefix("3."))
    }
}
