import Foundation

/// Where a scrap came from and how to get back there.
public struct Reference: Sendable, Equatable {
    public var provider: ProviderID
    /// The source app; nil only when no external app was known at capture time.
    public var app: AppIdentity?
    /// Window title at capture time.
    public var window: String?
    public var locator: Locator
    /// What "Open source" launches, for example a text-fragment URL or `message://`.
    public var deepLink: URL?
    /// Short line shown on the card, for example "zillow.com" or "Mail · landlord".
    public var label: String
    public var fingerprint: Fingerprint

    public init(
        provider: ProviderID,
        app: AppIdentity?,
        window: String? = nil,
        locator: Locator,
        deepLink: URL? = nil,
        label: String,
        fingerprint: Fingerprint
    ) {
        self.provider = provider
        self.app = app
        self.window = window
        self.locator = locator
        self.deepLink = deepLink
        self.label = label
        self.fingerprint = fingerprint
    }
}

/// The provider that built a reference. A string rather than a closed enum, so a file written
/// by a newer version with an unknown provider still loads.
public struct ProviderID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let safari = ProviderID(rawValue: "safari")
    public static let mail = ProviderID(rawValue: "mail")
    public static let files = ProviderID(rawValue: "files")
    public static let screenshot = ProviderID(rawValue: "screenshot")
    public static let fallback = ProviderID(rawValue: "fallback")
}

/// Provider-specific position of the source. Every case the MVP providers need is defined now,
/// so later providers don't change the file format.
public enum Locator: Sendable, Equatable {
    /// The app and window alone (fallback provider).
    case app
    /// A web page (Safari).
    case url(URL)
    /// A Mail message, by its Message-ID without angle brackets.
    case messageID(String)
    /// A local file: its path and a bookmark (not security-scoped).
    case file(path: String, bookmark: Data)
    /// A screenshot's capture rectangle, in global screen points.
    case screenRect(ScreenRect)
}

/// A rectangle in screen points. Its own type so ScrapModel needs no graphics framework.
public struct ScreenRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// An app by bundle identifier. Only the bundle id is written to files; the name is looked up
/// when it's shown. Equality and hashing use the bundle id alone, so an identity read back from
/// a file equals the one captured, and exclusion-list matches don't depend on the name.
public struct AppIdentity: Hashable, Sendable {
    public var bundleID: String
    /// The app's display name, when known. Never written to files.
    public var name: String?

    public init(bundleID: String, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }

    public static func == (lhs: AppIdentity, rhs: AppIdentity) -> Bool {
        lhs.bundleID == rhs.bundleID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
}

/// Health of a reference. Kept in the index only; health checks never write scrap files.
public enum ReferenceStatus: String, Sendable, CaseIterable {
    case ok, changed, trashed, missing, unknown
}

/// A reference's last health check, as stored in the index.
public struct ReferenceHealth: Sendable, Equatable {
    public var status: ReferenceStatus
    public var lastChecked: Date

    public init(status: ReferenceStatus, lastChecked: Date) {
        self.status = status
        self.lastChecked = lastChecked
    }
}

/// A content hash, written as `sha256:<hex>`. Used for change detection and duplicates.
public struct Fingerprint: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
