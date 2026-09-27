import CryptoKit
import Foundation

/// The two values that let the app download reports from IBKR. Neither can
/// trade or move money — they only unlock the read-only Flex report.
public struct Credentials: Codable, Sendable, Equatable {
    public var token: String
    public var queryId: String

    public init(token: String, queryId: String) {
        self.token = token
        self.queryId = queryId
    }
}

/// Keeps the IBKR token and Query ID in a file in the app's folder, locked with
/// a key held by the Mac's security chip (the Secure Enclave). The chip never
/// hands that key out, so the file can't be opened on any other computer, and
/// nothing depends on how the app is signed, so rebuilding it changes nothing.
public enum CredentialStore {
    /// ~/Library/Application Support/Portfolio/credentials.sealed
    static var file: URL { AccountCache.directory.appendingPathComponent("credentials.sealed") }

    private static let lock = NSLock()
    private static var didRead = false
    private static var remembered: Credentials?

    public static func load() -> Credentials? {
        lock.withLock {
            if !didRead {
                remembered = try? readFile()
                didRead = true
            }
            return remembered
        }
    }

    public static func save(_ c: Credentials) throws {
        try lock.withLock {
            try writeFile(c)
            (remembered, didRead) = (c, true)
        }
    }

    public static func clear() {
        lock.withLock {
            try? FileManager.default.removeItem(at: file)
            (remembered, didRead) = (nil, true)
        }
    }

    // MARK: The locked file

    /// What's in the file. `chipKey` is a reference only this Mac's chip can
    /// use, not the key itself; together with the throwaway `oneOffKey` it gives
    /// the key that locks `sealed`.
    private struct SealedFile: Codable {
        var chipKey: Data
        var oneOffKey: Data
        var sealed: Data
    }

    private static func writeFile(_ c: Credentials) throws {
        do {
            let chipKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let oneOff = P256.KeyAgreement.PrivateKey()
            let oneOffKey = oneOff.publicKey.rawRepresentation
            let key = lockKey(try oneOff.sharedSecretFromKeyAgreement(with: chipKey.publicKey), oneOffKey: oneOffKey)
            guard let sealed = try AES.GCM.seal(JSONEncoder().encode(c), using: key).combined else {
                throw CocoaError(.coderInvalidValue)
            }
            let contents = SealedFile(chipKey: chipKey.dataRepresentation, oneOffKey: oneOffKey, sealed: sealed)
            try FileManager.default.createDirectory(at: AccountCache.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            throw FlexError(message: "Couldn't save the IBKR details on this Mac (\(error.localizedDescription)).")
        }
    }

    /// Fails when there's no file, or it was made on another Mac or is damaged.
    private static func readFile() throws -> Credentials? {
        let contents = try JSONDecoder().decode(SealedFile.self, from: Data(contentsOf: file))
        let chipKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: contents.chipKey)
        let oneOff = try P256.KeyAgreement.PublicKey(rawRepresentation: contents.oneOffKey)
        let key = lockKey(try chipKey.sharedSecretFromKeyAgreement(with: oneOff), oneOffKey: contents.oneOffKey)
        let json = try AES.GCM.open(AES.GCM.SealedBox(combined: contents.sealed), using: key)
        let c = try JSONDecoder().decode(Credentials.self, from: json)
        return c.token.isEmpty || c.queryId.isEmpty ? nil : c
    }

    private static func lockKey(_ secret: SharedSecret, oneOffKey: Data) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: oneOffKey,
                                       sharedInfo: Data("Portfolio IBKR credentials".utf8), outputByteCount: 32)
    }
}
