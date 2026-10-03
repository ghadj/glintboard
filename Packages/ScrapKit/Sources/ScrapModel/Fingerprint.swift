import CryptoKit
import Foundation

extension Fingerprint {
    /// SHA-256 of captured text after Unicode NFC normalization, whitespace collapsing, and
    /// trimming, so text that differs only in composition or spacing gets the same fingerprint.
    public static func text(_ text: String) -> Fingerprint {
        data(Data(normalized(text).utf8))
    }

    /// SHA-256 of the bytes as given (image bytes for images).
    public static func data(_ data: Data) -> Fingerprint {
        let digest = SHA256.hash(data: data)
        var hex = "sha256:"
        hex.reserveCapacity(hex.count + 2 * SHA256.byteCount)
        for byte in digest {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0F)])
        }
        return Fingerprint(rawValue: hex)
    }

    private static let hexDigits = Array("0123456789abcdef")

    /// NFC, then every run of Unicode whitespace (the `White_Space` property: spaces, tabs,
    /// line breaks, no-break and ideographic spaces) becomes one space, then leading and
    /// trailing whitespace is dropped.
    static func normalized(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace {
                    result.append(" ")
                    pendingSpace = false
                }
                result.append(scalar)
            }
        }
        return String(result)
    }
}
