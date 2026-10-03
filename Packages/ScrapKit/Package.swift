// swift-tools-version: 6.0
// Core logic for the app, testable without AppKit. Layering is enforced by target
// dependencies: Model <- Storage <- Capture. No package dependencies (native only).
import PackageDescription

let package = Package(
    name: "ScrapKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScrapModel", targets: ["ScrapModel"]),
        .library(name: "ScrapStorage", targets: ["ScrapStorage"]),
        .library(name: "ScrapCapture", targets: ["ScrapCapture"]),
    ],
    targets: [
        // Foundation only: value types, frontmatter codec, fingerprints, ranks, layout math.
        .target(name: "ScrapModel"),
        // File store, SQLite index, reconciliation.
        .target(
            name: "ScrapStorage",
            dependencies: ["ScrapModel"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Capture pipeline, privacy filter, providers, system-client protocols.
        .target(name: "ScrapCapture", dependencies: ["ScrapModel", "ScrapStorage"]),
        // Fakes for every system client. Linked only by test targets.
        .target(name: "ScrapTestSupport", dependencies: ["ScrapModel", "ScrapStorage", "ScrapCapture"]),

        .testTarget(name: "ScrapModelTests", dependencies: ["ScrapModel", "ScrapTestSupport"]),
        .testTarget(name: "ScrapStorageTests", dependencies: ["ScrapStorage", "ScrapTestSupport"]),
        .testTarget(name: "ScrapCaptureTests", dependencies: ["ScrapCapture", "ScrapTestSupport"]),
    ]
)
