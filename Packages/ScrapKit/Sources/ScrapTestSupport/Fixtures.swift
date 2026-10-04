import Foundation

/// Hand-written fixture files in `Packages/ScrapKit/Tests/Fixtures/`, read from the source tree.
public enum Fixtures {
    /// `Tests/Fixtures/Library`.
    public static let library: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ScrapTestSupport
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // ScrapKit
        .appending(path: "Tests/Fixtures/Library", directoryHint: .isDirectory)

    /// The bytes of a fixture, by path relative to `library`.
    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: library.appending(path: relativePath))
    }

    /// The text of a fixture, by path relative to `library`.
    public static func text(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
    }
}
