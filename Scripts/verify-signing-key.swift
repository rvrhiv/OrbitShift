import CryptoKit
import Foundation

// Only the public key is an argument. The private seed arrives through stdin.
guard CommandLine.arguments.count == 2,
  let expected = Data(base64Encoded: CommandLine.arguments[1]), expected.count == 32,
  let encoded = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8),
  let seed = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
  seed.count == 32,
  let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
  key.publicKey.rawRepresentation == expected
else {
  fputs(
    "Signing key does not match OrbitShift’s public key, or is not a Sparkle 2.10 seed.\n", stderr)
  exit(1)
}
print("OrbitShift signing key matches its public key.")
