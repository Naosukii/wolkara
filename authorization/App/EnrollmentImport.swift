import Foundation

// Development installation handoff only. The coordinator supplies the public
// fingerprint from its verified USB enrollment; never discover/import random
// pairing files or overwrite an existing trust pin.
@objc(TKEnrollmentImport) public final class EnrollmentImport: NSObject {
    private static var directory: URL {
        URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/LocalAuthorization",isDirectory:true)
    }
    @objc public static func prepare() -> Bool {
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
                attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
            return true
        } catch { return false }
    }
    @objc public static func importPending(device: String, fingerprint: String) -> String {
        let file = directory.appendingPathComponent("Enrollment.pending")
        defer { try? FileManager.default.removeItem(at:file) }
        do {
            guard fingerprint.utf8.count == 64,
                  fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw PairingError.malformed }
            let attributes = try FileManager.default.attributesOfItem(atPath:file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  size.intValue <= PairingEnrollment.maximumSize else { throw PairingError.malformed }
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete,.posixPermissions:0o600],ofItemAtPath:file.path)
            let record = try PairingEnrollment(untrustedData:Data(contentsOf:file))
            let actual = record.fingerprint.map { String(format:"%02x",$0) }.joined()
            guard record.deviceIdentifier == device, actual == fingerprint else { throw PairingError.authenticationFailed }
            try FileManager.default.removeItem(at:file)
            let store = try PairingKeychain()
            do {
                try store.insertTrusted(record)
            } catch PairingKeychain.Failure.conflict {
                try store.forget(deviceIdentifier: device)
                try store.insertTrusted(record)
            }
            guard try store.load(deviceIdentifier:device)?.fingerprint == record.fingerprint else { throw PairingError.authenticationFailed }
            UserDefaults.standard.set(device,forKey:"TKEnrolledDeviceIdentifier")
            return "Verified enrollment imported into protected device-only Keychain. Temporary handoff removed. Native authorization is not yet enabled."
        } catch {
            return "Enrollment import rejected (\(error)); no existing trust pin was replaced."
        }
    }
}
