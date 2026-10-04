# Releasing OrbitShift

The manual **Release** workflow builds a universal macOS app from a fixed `main` commit, signs update metadata and publishes GitHub Release assets. Local Dev builds never publish anything.

## Signing

OrbitShift uses its own Ed25519 key for [Sparkle](https://sparkle-project.org/documentation/) updates. The public key is committed in `Config/App-Info.plist`. The private key belongs in the macOS Keychain account `com.rvrhiv.OrbitShift.release` and the `SPARKLE_PRIVATE_KEY` secret of the GitHub **release** environment. Never commit or log it, and keep a secure backup for future updates.

To initialize a new channel, generate its key once:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.rvrhiv.OrbitShift.release
```

Commit only the resulting `SUPublicEDKey`. Export the seed with `generate_keys --account com.rvrhiv.OrbitShift.release -x PATH_OUTSIDE_REPOSITORY` when provisioning CI, store it as the environment secret, and remove the temporary export. The signing script verifies that the private key matches the public key before signing. Do not regenerate or replace a published channel's key without an update migration plan.

**Apple signing is separate.** Distribution builds currently use ad-hoc code signing and are not notarized. Their download instructions disclose the first-launch macOS confirmation. Developer ID signing and notarization are not configured in this workflow; Sparkle signatures do not replace them. Keep Gatekeeper enabled.

## Publish a version

1. Push the intended source and documentation changes to `main`.
2. Add `docs/releases/VERSION.md` for curated notes, or let the workflow generate notes from the fixed commit.
3. Run **Actions → Release → Run workflow**, select `main`, and enter a new version such as `0.1.1` without a `v` prefix.
4. The workflow rejects an existing version/tag and assigns a build number above the last public appcast. Only the CI checkout is stamped.
5. The build job compiles and checks sources, then packages arm64 and x86_64 into one `OrbitShift.app`.
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

Use the version/build currently in `Config/App-Info.plist`. These commands require the matching Keychain key and release notes and leave artifacts in `build/releases/VERSION/`; they do not publish. Packaging refuses to overwrite an existing output directory.

Before publishing, verify app identity, architectures, signatures, first launch and the release notes. For subsequent releases, also check an actual upgrade, cancellation, offline behavior, signature rejection and preference persistence. The first release has no earlier public version from which to verify an upgrade.
