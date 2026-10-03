// swift-tools-version: 6.0
// Core logic for the app, testable without AppKit. Layering follows the target
// dependencies, Model <- Storage <- Capture, and scripts/check-layering.sh enforces it
// (incremental builds can miss a forbidden import). No package dependencies (native only).
import PackageDescription

// Matches the App target's SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY.
let swiftSettings: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

let package = Package(
    name: "ScrapKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScrapModel", targets: ["ScrapModel"]),
        .library(name: "ScrapStorage", targets: ["ScrapStorage"]),
        .library(name: "ScrapCapture", targets: ["ScrapCapture"]),
        // Fakes for AppTests. Link it only to test targets, never to the app.
        .library(name: "ScrapTestSupport", targets: ["ScrapTestSupport"]),
    ],
    targets: [
        // Foundation and CryptoKit only: value types, frontmatter codec, fingerprints, ranks, layout math.
        .target(name: "ScrapModel", swiftSettings: swiftSettings),
        // File store, SQLite index, reconciliation.
        .target(
            name: "ScrapStorage",
            dependencies: ["ScrapModel"],
            swiftSettings: swiftSettings,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Capture pipeline, privacy filter, providers, system-client protocols.
        .target(name: "ScrapCapture", dependencies: ["ScrapModel", "ScrapStorage"], swiftSettings: swiftSettings),
        // Fakes for every system client. Linked only by test targets.
        .target(
            name: "ScrapTestSupport",
            dependencies: ["ScrapModel", "ScrapStorage", "ScrapCapture"],
            swiftSettings: swiftSettings
        ),

        .testTarget(
            name: "ScrapModelTests",
            dependencies: ["ScrapModel", "ScrapTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ScrapStorageTests",
            dependencies: ["ScrapStorage", "ScrapTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ScrapCaptureTests",
            dependencies: ["ScrapCapture", "ScrapTestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
