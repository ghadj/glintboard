import ScrapModel

/// Something that changed in the library folder. Paths are relative to the library root.
public enum LibraryChange: Sendable, Equatable {
    /// The store wrote this scrap (a capture or an edit made in the app).
    case saved(Scrap, file: ScrapFileInfo)
    /// A scrap file was created or changed outside the app.
    case updated(Scrap, file: ScrapFileInfo)
    /// A scrap file is gone. The id is known if the store had read the file.
    case removed(path: String, id: ScrapID?)
    /// A scrap file changed outside the app and can't be read; it's left as it is.
    case problem(path: String, CodecError)
    /// Changes were lost (FSEvents dropped events, or the root moved); the folder needs a rescan.
    case rescanNeeded

    /// The file the change is about, if any.
    public var path: String? {
        switch self {
        case .saved(_, let file), .updated(_, let file): file.path
        case .removed(let path, _), .problem(let path, _): path
        case .rescanNeeded: nil
        }
    }
}
