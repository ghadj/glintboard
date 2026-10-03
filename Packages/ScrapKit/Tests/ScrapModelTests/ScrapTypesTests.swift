import Foundation
import ScrapModel
import Testing

struct ScrapTypesTests {
    /// Fails to compile if any public model type stops being `Sendable`.
    @Test func publicTypesAreSendable() {
        requireSendable(ScrapID.self)
        requireSendable(ScrapKind.self)
        requireSendable(Scrap.self)
        requireSendable(Note.self)
        requireSendable(AssetRef.self)
        requireSendable(Reference.self)
        requireSendable(ProviderID.self)
        requireSendable(Locator.self)
        requireSendable(ScreenRect.self)
        requireSendable(ReferenceStatus.self)
        requireSendable(ReferenceHealth.self)
        requireSendable(Fingerprint.self)
        requireSendable(Rank.self)
        requireSendable(AppIdentity.self)
        requireSendable(CollectionInfo.self)
        requireSendable(CaptureContext.self)
        requireSendable(CaptureTrigger.self)
        requireSendable(PasteboardItemSnapshot.self)
        requireSendable(FrontmatterEntry.self)
        requireSendable(FrontmatterValue.self)
        requireSendable(SystemWallClock.self)
    }

    @Test func shortHexIsFirstFourLowercaseHexDigits() throws {
        let uuid = try #require(UUID(uuidString: "8F3A0C2D-5D0F-4C8E-9A51-3C1E7A2B71E4"))
        #expect(ScrapID(raw: uuid).shortHex == "8f3a")
    }

    @Test func idStringIsLowercaseUUID() throws {
        let uuid = try #require(UUID(uuidString: "8F3A0C2D-5D0F-4C8E-9A51-3C1E7A2B71E4"))
        #expect(ScrapID(raw: uuid).stringValue == "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4")
    }

    @Test func idParsesEitherCase() throws {
        let lower = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))
        let upper = try #require(ScrapID(string: "8F3A0C2D-5D0F-4C8E-9A51-3C1E7A2B71E4"))
        #expect(lower == upper)
        #expect(ScrapID(string: "not-an-id") == nil)
    }

    @Test func idEncodesAsPlainString() throws {
        let id = try #require(ScrapID(string: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"))
        let json = try JSONEncoder().encode([id])
        #expect(String(decoding: json, as: UTF8.self) == #"["8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"]"#)
        #expect(try JSONDecoder().decode([ScrapID].self, from: json) == [id])
    }

    @Test func newScrapHasCurrentSchemaAndEmptyAIFields() {
        let scrap = Self.textScrap()
        #expect(scrap.schema == ScrapSchema.current)
        #expect(scrap.derivedFrom.isEmpty)
        #expect(scrap.aiExcluded == false)
        #expect(scrap.note == nil)
        #expect(scrap.asset == nil)
        #expect(scrap.pinned == false)
        #expect(scrap.extraFrontmatter.isEmpty)
    }

    @Test func unknownProviderIDIsKept() {
        let id = ProviderID(rawValue: "notes")
        #expect(id != .fallback)
        #expect(ProviderID(rawValue: "fallback") == .fallback)
    }

    @Test func providerIDsMatchDesignNames() {
        let names = [ProviderID.safari, .mail, .files, .screenshot, .fallback].map(\.rawValue)
        #expect(names == ["safari", "mail", "files", "screenshot", "fallback"])
    }

    @Test func kindAndStatusRawValuesMatchDesignNames() {
        #expect(ScrapKind.allCases.map(\.rawValue) == ["text", "link", "image", "file"])
        #expect(ReferenceStatus.allCases.map(\.rawValue) == ["ok", "changed", "trashed", "missing", "unknown"])
    }

    @Test func rankOrdersByBytes() {
        // "Z" (0x5A) sorts before "a" (0x61): base-62 digits are ordered by ASCII.
        #expect(Rank(rawValue: "Z") < Rank(rawValue: "a"))
        #expect(Rank(rawValue: "a") < Rank(rawValue: "a0"))
        #expect(!(Rank(rawValue: "b") < Rank(rawValue: "b")))
    }

    @Test func appIdentityComparesByBundleIDOnly() {
        let named = AppIdentity(bundleID: "com.apple.TextEdit", name: "TextEdit")
        let unnamed = AppIdentity(bundleID: "com.apple.TextEdit")
        #expect(named == unnamed)
        #expect(Set([named, unnamed]).count == 1)
        #expect(named != AppIdentity(bundleID: "com.apple.Safari", name: "TextEdit"))
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    static func textScrap() -> Scrap {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        return Scrap(
            id: ScrapID(),
            kind: .text,
            title: "2BR on Elm St",
            body: "2BR, 850 sq ft",
            board: Rank(rawValue: "a"),
            created: date,
            updated: date,
            reference: Reference(
                provider: .fallback,
                app: AppIdentity(bundleID: "com.apple.TextEdit"),
                locator: .app,
                label: "TextEdit",
                fingerprint: Fingerprint(rawValue: "sha256:00")
            )
        )
    }
}
