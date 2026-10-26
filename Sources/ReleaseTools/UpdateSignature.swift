import CryptoKit
import Foundation

/// Checks a Sparkle EdDSA update signature against the public key the app
/// ships with, so a release signed with the wrong private key never goes out.
/// `sign_update --verify` can't catch that: it derives the public key from the
/// private key it was given.
public enum UpdateSignature {
    /// Why the inputs could not be checked at all.
    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case publicKeyIsNotBase64
        case signatureIsNotBase64
        case publicKeyIsNotEd25519

        public var description: String {
            switch self {
            case .publicKeyIsNotBase64: "public key is not base64"
            case .signatureIsNotBase64: "signature is not base64"
            case .publicKeyIsNotEd25519: "public key is not a 32-byte Ed25519 key"
            }
        }
    }

    /// True when `signature` (base64) is a valid Ed25519 signature of `data`
    /// under `publicKey` (base64, as in `SUPublicEDKey`). Throws only when an
    /// input can't be decoded.
    public static func isValid(signature: String, publicKey: String, data: Data) throws -> Bool {
        guard let keyBytes = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Error.publicKeyIsNotBase64
        }
        guard let signatureBytes = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Error.signatureIsNotBase64
        }
        let key: Curve25519.Signing.PublicKey
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        } catch {
            throw Error.publicKeyIsNotEd25519
        }
        return key.isValidSignature(signatureBytes, for: data)
    }
}
