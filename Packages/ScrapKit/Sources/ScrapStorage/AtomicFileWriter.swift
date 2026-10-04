import Foundation

/// Writes files so a crash never leaves a half-written one. The bytes go to a temporary file in
/// the target's folder (`.<name>.<uuid>.tmp`), are flushed to the drive, and the temporary file
/// is then renamed over the target, which is atomic on one volume. If anything fails, the
/// temporary file is removed and the target is untouched; a crash can leave only a temporary
/// file, which `ScrapStore.open()` removes.
///
/// Replacing a file creates a new one (mode 0644, less the umask), so permissions, extended
/// attributes such as Finder tags, and hard links on the old file aren't carried over, and a
/// symlinked file is replaced by a regular one. The app only replaces files it writes itself.
enum AtomicFileWriter {
    enum Mode {
        /// Replace the target if it exists.
        case replace
        /// Create the target only if it doesn't exist yet; an existing file is kept.
        case createOnly
    }

    /// `.<name>.<uuid>.tmp`. The name part is cut to at most 200 bytes (at a character boundary),
    /// so the result stays within the file system's 255-byte limit for names near that limit.
    static func temporaryName(for name: String) -> String {
        var part = ""
        for character in name {
            guard part.utf8.count + character.utf8.count <= 200 else { break }
            part.append(character)
        }
        return "." + part + "." + UUID().uuidString + ".tmp"
    }

    /// True for names `temporaryName(for:)` makes: a leading dot, a name, a UUID, and `.tmp`.
    static func isTemporaryName(_ name: String) -> Bool {
        guard name.hasPrefix("."), name.hasSuffix(".tmp") else { return false }
        let stem = name.dropFirst().dropLast(".tmp".count)
        guard let dot = stem.lastIndex(of: "."), dot > stem.startIndex else { return false }
        return UUID(uuidString: String(stem[stem.index(after: dot)...])) != nil
    }

    /// Writes `data` to `url`. Returns false only in `.createOnly` mode when the target already
    /// exists (and is kept). `label` names the file in errors.
    @discardableResult
    static func write(_ data: Data, to url: URL, label: String, mode: Mode = .replace) throws(StoreError) -> Bool {
        let targetPath = url.path(percentEncoded: false)
        let temporaryPath = url.deletingLastPathComponent()
            .appending(path: temporaryName(for: url.lastPathComponent)).path(percentEncoded: false)

        let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw .writeFailed(path: label) }
        var renamed = false
        defer {
            if !renamed { unlink(temporaryPath) }
        }

        let written = writeAll(data, to: descriptor) && flush(descriptor)
        let closed = close(descriptor) == 0
        guard written, closed else { throw .writeFailed(path: label) }

        // The folder itself isn't flushed after the rename: a crash right after it can bring the
        // previous version back, which is still a whole file. Data safety needs atomicity here,
        // not that last write.
        switch mode {
        case .replace:
            guard rename(temporaryPath, targetPath) == 0 else { throw .writeFailed(path: label) }
        case .createOnly:
            // Fails with EEXIST instead of replacing, so there's no check-then-write window.
            if renamex_np(temporaryPath, targetPath, UInt32(RENAME_EXCL)) != 0 {
                let error = errno
                if error == EEXIST { return false }
                guard error == ENOTSUP || error == EINVAL else { throw .writeFailed(path: label) }
                return try createWithoutExclusiveRename(
                    from: temporaryPath, to: targetPath, label: label, renamed: &renamed)
            }
        }
        renamed = true
        return true
    }

    /// For volumes without `RENAME_EXCL` (some network and external file systems): a hard link
    /// is just as exclusive, and where links aren't supported either, check and then rename.
    private static func createWithoutExclusiveRename(
        from temporaryPath: String, to targetPath: String, label: String, renamed: inout Bool
    ) throws(StoreError) -> Bool {
        if link(temporaryPath, targetPath) == 0 {
            // The target now exists; the temporary name is removed by the caller's cleanup.
            return true
        }
        let error = errno
        if error == EEXIST { return false }
        guard error == ENOTSUP || error == EPERM || error == EXDEV else { throw .writeFailed(path: label) }
        if access(targetPath, F_OK) == 0 { return false }
        guard rename(temporaryPath, targetPath) == 0 else { throw .writeFailed(path: label) }
        renamed = true
        return true
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return true }
            var remaining = buffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                pointer += count
                remaining -= count
            }
            return true
        }
    }

    /// `F_FULLFSYNC` makes the drive itself flush, which `fsync` doesn't on macOS. Where a file
    /// system doesn't support it, `fsync` is the best available.
    private static func flush(_ descriptor: Int32) -> Bool {
        fcntl(descriptor, F_FULLFSYNC) != -1 || fsync(descriptor) == 0
    }
}
