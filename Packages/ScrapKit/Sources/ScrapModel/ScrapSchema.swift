/// Version of the scrap file format, written as `schema` in every scrap's frontmatter.
///
/// Changing the schema needs a migration plan first (see `AGENTS.md`).
public enum ScrapSchema {
    public static let current = 1
}
