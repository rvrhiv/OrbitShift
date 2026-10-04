# Releasing OrbitShift

The manual **Release** workflow builds a universal macOS app from a fixed `main` commit, signs the app with a persistent certificate, signs update metadata and publishes GitHub Release assets. Local Dev builds never publish anything.

## Signing

OrbitShift uses its own Ed25519 key for [Sparkle](https://sparkle-project.org/documentation/) updates. The public key is committed in `Config/App-Info.plist`. The private key belongs in the macOS Keychain account `com.rvrhiv.OrbitShift.release` and the `SPARKLE_PRIVATE_KEY` secret of the GitHub **release** environment. Never commit or log it, and keep a secure backup for future updates.

To initialize a new channel, generate its key once:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.rvrhiv.OrbitShift.release
```

Commit only the resulting `SUPublicEDKey`. Export the seed with `generate_keys --account com.rvrhiv.OrbitShift.release -x PATH_OUTSIDE_REPOSITORY` when provisioning CI, store it as the environment secret, and remove the temporary export. The signing script verifies that the private key matches the public key before signing. Do not regenerate or replace a published channel's key without an update migration plan.

### Persistent code signing

Starting with 0.1.2, distribution builds use the self-signed **OrbitShift Release** identity. Its public certificate is pinned in `Config/Release-Certificate.pem`; its private key stays in the maintainer's login Keychain and the GitHub **release** environment. Each signature's designated requirement contains the bundle identifier and the certificate fingerprint, so macOS can recognize subsequent versions for Accessibility. A missing or different identity stops the build and packaging; there is no ad-hoc fallback.

The existing certificate must be reused for every release. On the maintainer's Mac, `python3 Scripts/setup-signing.py distribution` checks that its private key is present. On a new Mac, restore the original identity from an encrypted PKCS#12 backup before building. Do not delete the pinned certificate to generate another one.

For the initial creation of an unpublished channel only, that command creates an identity if no certificate has been pinned yet. Commit only the public PEM. It does not install a trusted root or alter the system trust store.

Provision these GitHub **release** environment secrets:

Keep the environment's deployment branch policy restricted to the `main` branch. Secrets are available to jobs using that environment, so anyone who can change and run an allowed workflow must be trusted with the signing keys. The public repository and public certificates do not expose the private keys. Protect maintainer accounts with strong authentication; log masking is not protection against a malicious workflow.

| Secret | Value |
| --- | --- |
| `ORBITSHIFT_CERTIFICATE_P12` | Base64-encoded, password-protected PKCS#12 export of **only** the OrbitShift Release identity |
| `ORBITSHIFT_CERTIFICATE_PASSWORD` | The export's strong password |
| `SPARKLE_PRIVATE_KEY` | The existing Sparkle signing seed described above |

Export the selected identity in Keychain Access, keep a secure backup outside the repository, transfer it through secret input rather than command logs, and remove temporary exports. Never export the whole login keychain. The build job imports this identity into a temporary keychain, checks it against the committed public certificate, and removes the keychain even if the build fails. Its Dev packaging check uses the same CI identity with the separate Dev bundle identifier; local development uses its own **OrbitShift Development** certificate.

Local Dev setup is `python3 Scripts/setup-signing.py`, once per signing identity. Preserve the private key in Keychain and the public `.local-builds/Development-Certificate.pem`. Re-running setup reuses the identity. `ORBITSHIFT_SIGNING_IDENTITY` and `ORBITSHIFT_SIGNING_KEYCHAIN` are explicit CI overrides; never use them to rotate an installed Dev app's identity.

**Migration:** versions 0.1.0, 0.1.1 and earlier Dev builds used ad-hoc signing. Their stored Accessibility grant cannot be carried over to a new certificate. Users grant access once after this transition; subsequent builds with the same certificate retain the grant. Production and Dev have separate permissions. Losing or rotating either private key requires another migration.

**Apple signing is separate.** These certificates provide continuity between app versions, not Apple Developer ID verification or notarization. Download instructions still disclose the first-launch macOS confirmation. Users do not need to import our certificate or change trust settings. Sparkle signatures continue to verify the update archive and feed. Keep Gatekeeper enabled. See Apple's [code-signing requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/).

## Publish a version

1. Push the intended source and documentation changes to `main`.
2. Add `docs/releases/VERSION.md` for curated notes, or let the workflow generate notes from the fixed commit.
3. Run **Actions → Release → Run workflow**, select `main`, and enter a new version such as `0.1.1` without a `v` prefix.
4. The workflow rejects an existing version/tag and assigns a build number above the last public appcast. Only the CI checkout is stamped.
5. The build job compiles and checks sources, imports the pinned signing identity, then signs and packages arm64 and x86_64 into one `OrbitShift.app`.
6. The publish job signs the archive, notes and appcast, verifies signatures/checksums, rechecks `main`, and publishes a release.

Each release contains:

| Asset | Purpose |
| --- | --- |
| `OrbitShift-VERSION.zip` | Universal app for users |
| `OrbitShift-VERSION.md` | Release notes |
| `appcast.xml` | Signed Sparkle update feed |
| `SHA256SUMS` | Checksums for the assets above |

The app reads the [latest appcast](https://github.com/rvrhiv/OrbitShift/releases/latest/download/appcast.xml). Installation and relaunch require a user action; automatic checks do not imply automatic installation.

Published versions and signed assets must not be overwritten. Inspect an interrupted draft before retrying, and fix an already published release with a new version.

## Local distribution check

```sh
bash Scripts/build-app.sh Release distribution
bash Scripts/package-release.sh 0.1.0 1
bash Scripts/sign-release.sh 0.1.0 1
```

Use the version/build currently in `Config/App-Info.plist`. These commands require the matching release certificate/private key, Sparkle key and release notes, and leave artifacts in `build/releases/VERSION/`; they do not publish. Packaging refuses to overwrite an existing output directory.

Before publishing, verify app identity, architectures, signatures, first launch and the release notes. For subsequent releases, also check an actual upgrade, cancellation, offline behavior, signature rejection and preference persistence. The first release has no earlier public version from which to verify an upgrade.
