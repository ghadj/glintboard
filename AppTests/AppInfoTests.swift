import Foundation
import Testing

@testable import App

struct AppInfoTests {
    @Test func displayNameMatchesInfoPlist() {
        let expected = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(AppInfo.displayName == expected)
        #expect(!AppInfo.displayName.isEmpty)
    }

    @Test func displayNamePrefersDisplayNameKey() {
        let info = AppInfo(infoDictionary: ["CFBundleDisplayName": "Shown", "CFBundleName": "Short"])
        #expect(info.displayName == "Shown")
    }

    @Test func displayNameFallsBackToBundleName() {
        let info = AppInfo(infoDictionary: ["CFBundleName": "Short"])
        #expect(info.displayName == "Short")
    }

    @Test func missingKeysGiveEmptyStrings() {
        let info = AppInfo(infoDictionary: [:])
        #expect(info.displayName.isEmpty)
        #expect(info.bundleIdentifier.isEmpty)
    }

    @Test func bundleIdentifierMatchesBundle() {
        #expect(AppInfo.bundleIdentifier == Bundle.main.bundleIdentifier)
    }
}
