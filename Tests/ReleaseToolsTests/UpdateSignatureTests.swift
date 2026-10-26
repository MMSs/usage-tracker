import CryptoKit
import Foundation
import Testing
@testable import ReleaseTools

@Suite struct UpdateSignatureTests {
    private let archive = Data("Usage-Tracker-1.0.0.zip bytes".utf8)

    private func sign(_ data: Data, with key: Curve25519.Signing.PrivateKey) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    private func publicKey(of key: Curve25519.Signing.PrivateKey) -> String {
        key.publicKey.rawRepresentation.base64EncodedString()
    }

    @Test func aSignatureFromTheMatchingKeyIsValid() throws {
        let key = Curve25519.Signing.PrivateKey()
        let valid = try UpdateSignature.isValid(
            signature: try sign(archive, with: key), publicKey: publicKey(of: key), data: archive
        )
        #expect(valid)
    }

    @Test func aSignatureFromAnotherKeyIsInvalid() throws {
        let appKey = Curve25519.Signing.PrivateKey()
        let otherKey = Curve25519.Signing.PrivateKey()
        let valid = try UpdateSignature.isValid(
            signature: try sign(archive, with: otherKey), publicKey: publicKey(of: appKey), data: archive
        )
        #expect(!valid)
    }

    @Test func aTamperedFileIsInvalid() throws {
        let key = Curve25519.Signing.PrivateKey()
        var tampered = archive
        tampered[0] ^= 0x01
        let valid = try UpdateSignature.isValid(
            signature: try sign(archive, with: key), publicKey: publicKey(of: key), data: tampered
        )
        #expect(!valid)
    }

    @Test func undecodableBase64Throws() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signature = try sign(archive, with: key)
        #expect(throws: UpdateSignature.Error.publicKeyIsNotBase64) {
            try UpdateSignature.isValid(signature: signature, publicKey: "not base64!", data: archive)
        }
        #expect(throws: UpdateSignature.Error.signatureIsNotBase64) {
            try UpdateSignature.isValid(signature: "not base64!", publicKey: publicKey(of: key), data: archive)
        }
    }

    @Test func aPublicKeyOfTheWrongLengthThrows() {
        let short = Data(repeating: 7, count: 16).base64EncodedString()
        #expect(throws: UpdateSignature.Error.publicKeyIsNotEd25519) {
            try UpdateSignature.isValid(signature: short, publicKey: short, data: archive)
        }
    }
}
