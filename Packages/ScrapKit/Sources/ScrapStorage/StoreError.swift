import ScrapModel

/// Why the store couldn't do something. Paths are relative to the library root.
public enum StoreError: Error, Equatable, Sendable {
    /// A folder couldn't be created.
    case cannotCreateFolder(path: String)
    /// A file couldn't be read from disk.
    case readFailed(path: String)
    /// A file couldn't be written.
    case writeFailed(path: String)
    /// A scrap file was read but isn't a valid scrap; it's left as it is.
    case unreadable(path: String, CodecError)
    /// A `.collection.json` was read but isn't valid; it's left as it is.
    case invalidCollectionFile(path: String)
    /// A `.collection.json` written with a newer schema than this version reads; it's left as it is.
    case newerCollectionSchema(path: String, Int)
}
