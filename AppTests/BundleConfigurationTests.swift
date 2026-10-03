import Foundation
import Security
import Testing

/// Checks the built app's Info.plist and code signature. The tests are hosted in the app,
/// so `Bundle.main` and `SecCodeCopySelf` describe the app itself.
struct BundleConfigurationTests {
    @Test func isMenuBarAgent() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test func targetsMacOS15() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String == "15.0")
    }

    @Test func hasAppleEventsEntitlement() throws {
        let entitlements = try signedEntitlements()
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true)
    }

    @Test func usesHardenedRuntime() throws {
        let flags = try #require(signingInformation()[kSecCodeInfoFlags as String] as? UInt32)
        #expect(SecCodeSignatureFlags(rawValue: flags).contains(.runtime))
    }

    @Test func isNotSandboxed() throws {
        let entitlements = try signedEntitlements()
        #expect(entitlements["com.apple.security.app-sandbox"] == nil)
    }

    #if DEBUG
        @Test func debugBuildUsesDevIdentity() {
            #expect(Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true)
        }
    #endif

    /// Fails, rather than passing vacuously, when the signature carries no entitlements.
    private func signedEntitlements() throws -> [String: Any] {
        try #require(signingInformation()[kSecCodeInfoEntitlementsDict as String] as? [String: Any])
    }

    private func signingInformation() throws -> [String: Any] {
        var code: SecCode?
        try #require(SecCodeCopySelf([], &code) == errSecSuccess)
        var staticCode: SecStaticCode?
        try #require(SecCodeCopyStaticCode(try #require(code), [], &staticCode) == errSecSuccess)
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        try #require(SecCodeCopySigningInformation(try #require(staticCode), flags, &info) == errSecSuccess)
        return try #require(info as? [String: Any])
    }
}
