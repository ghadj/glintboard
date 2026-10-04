import Foundation
import ScrapModel

/// Where the library lives by default.
public enum LibraryLocation {
    /// `~/Library/Application Support/<bundle id>/Library`. The bundle id comes from the app, so a
    /// Dev build (bundle id ending in `.dev`) gets its own folder.
    public static func defaultRoot(
        bundleIdentifier: String, applicationSupport: URL = .applicationSupportDirectory
    ) -> URL {
        applicationSupport
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Library", directoryHint: .isDirectory)
    }
}

/// Names and places inside the library folder. File names are for people only; a scrap's id
/// comes from its frontmatter, never from its file name.
public enum LibraryLayout {
    /// In each collection folder: display order and creation date.
    public static let collectionFileName = ".collection.json"
    /// In each collection folder: stored images and file thumbnails.
    public static let assetsFolderName = "assets"
    /// At the root: deleted scraps, moved here with a timestamp.
    public static let trashFolderName = ".trash"
    /// At the root: the search index, a rebuildable cache.
    public static let indexFileName = ".index.sqlite"

    /// `yyyy-MM-dd-HHmm-<first 4 hex of id>.md`, in the given (normally local) time zone, so
    /// the name matches the clock the user saw when capturing.
    public static func fileName(created: Date, id: ScrapID, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: created)
        return pad(parts.year, 4) + "-" + pad(parts.month, 2) + "-" + pad(parts.day, 2) + "-"
            + pad(parts.hour, 2) + pad(parts.minute, 2) + "-" + id.shortHex + ".md"
    }

    /// `name` if no existing name matches it, otherwise `name` with `-2`, `-3`, … before its
    /// extension. Names are compared as the default macOS file system (APFS) does: ignoring
    /// case and Unicode composition.
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        func folded(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
        let taken = Set(existing.map(folded))
        guard taken.contains(folded(name)) else { return name }
        let (stem, suffix): (Substring, Substring)
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            (stem, suffix) = (name[..<dot], name[dot...])
        } else {
            (stem, suffix) = (name[...], "")
        }
        var number = 2
        while true {
            let candidate = "\(stem)-\(number)\(suffix)"
            if !taken.contains(folded(candidate)) { return candidate }
            number += 1
        }
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let digits = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
