# Contributing to OrbitShift

Requires macOS 14+ and Xcode with Swift 6.0+. Open `Package.swift` in Xcode, or use the command line. SwiftPM resolves the pinned Sparkle dependency; no Node, Homebrew or XcodeGen setup is needed.

## Build and check

```sh
swift build
swift format lint --strict --recursive Package.swift App Sources Scripts/generate-icon.swift Scripts/verify-signing-key.swift
plutil -lint Config/App-Info.plist
for script in Scripts/*.sh; do bash -n "$script"; done
python3 Scripts/setup-signing.py
bash Scripts/build-app.sh Release
open 'build/OrbitShift Dev.app'
```

Use the packaged app to check permissions and login items. `swift run` does not provide the same app identity.

Both Debug and Release default to the development flavor: **OrbitShift Dev**, bundle ID `com.rvrhiv.OrbitShift.dev`, and a display version such as `0.1.0-dev.1`. Distribution uses `com.rvrhiv.OrbitShift` and separate preferences.

The packaging script keeps one Dev app in `build/`. It compiles, packages and verifies the next app before replacing the previous one. Failed builds preserve the old app. Quit a running copy first. Incremental SwiftPM caches are reused; unrelated applications are not removed.

Local apps use a persistent self-signed certificate. `setup-signing.py` creates it once in your login Keychain, or reuses it, and pins its public certificate in `.local-builds/Development-Certificate.pem`. Do not delete the private key or replace the certificate between builds. The build fails when the expected identity is unavailable; it never falls back to ad-hoc signing. Back up the identity as an encrypted PKCS#12 file outside the repository.

The first migration from the old ad-hoc signature requires a new Accessibility grant. Afterwards, builds signed with the same certificate preserve the grant. This does not require an Apple Developer subscription, installing a trusted root, changing TCC data, or disabling Gatekeeper. Moving to another Mac or rotating/loss of the signing key requires a new grant.

## Code map

| Path | Responsibility |
| --- | --- |
| `Sources/OrbitShiftCore` | Supported keys, single-press state, preferences and input-source cycle |
| `App/KeyboardMonitor.swift` | Active event tap, per-side modifiers, permission state and recovery |
| `App/InputSourceController.swift` | Text Input Source Services and macOS source-change notifications |
| `App/AppModel.swift` | Settings persistence and coordination |
| `App/OrbitShiftApp.swift` | Menu bar, settings-window lifecycle and native permission guidance |
| `App/SettingsView.swift` | English/Russian interface and isolated preview |
| `App/UpdateController.swift`, `App/UpdateUserDriver.swift` | Sparkle checks, signature policy and explicit installation consent |
| `Scripts/build_app.py` | Packaging, Dev version counter and safe app replacement |
| `Scripts/code_signing.py`, `Scripts/setup-signing.py` | Stable channel certificates and signature verification |

## Behavior to preserve

- Switch once on release of a lone trigger. Another key held before or during the press cancels it; repeats never switch again.
- Use the actual macOS source as the starting point. Wrap the configured cycle, skip unavailable sources, and do not report failed selection as success.
- Clear an unfinished press on pause, reassignment, sleep or loss of the event tap.
- Show native permission guidance only on first setup or explicit user action. Granted access must not prompt. Request Input Monitoring only when needed to start the tap.
- Keep the settings window open when macOS settings close. Closing OrbitShift's window returns the app to menu bar mode.
- Do not record typed text. Preserve unreadable or future preferences rather than overwriting them.

## Diagnostics and screenshots

```sh
'build/OrbitShift Dev.app/Contents/MacOS/OrbitShift' --diagnostics
open 'build/OrbitShift Dev.app' --args --demo --language en
```

Diagnostics read sources and permissions without installing a keyboard handler. Permission results for a process launched from a terminal can differ from the app opened through LaunchServices; verify the real app as well.

Demo mode uses example sources and does not change saved settings, login items or input sources, or run the updater. Use `--language ru` for Russian. Close another instance of the same bundle before launching a preview. README images are window captures of this mode, not evidence of physical keyboard behavior.

For a rendered UI preview:

```sh
'build/OrbitShift Dev.app/Contents/MacOS/OrbitShift' --demo --render-preview /tmp/orbitshift.png --language en --page switching --dark
```

## Manual checks

Verify physical Fn/Globe, Fn + Delete/arrows/media, the selected left/right modifier, fast typing, external source changes and source reordering. Check that the macOS indicator and actual typed text agree in an editor and browser. Also check permission recovery, pause/resume, sleep, keyboard reconnects and login-item behavior when changing those paths.

When changing signing, grant Accessibility to a packaged build, quit it, change and rebuild it, then reopen the same app path. Confirm that System reports access and an active handler without opening macOS permission settings, and check physical Fn again. Compare `codesign -d -r-` for both builds: the designated requirement must still contain the same bundle identifier and certificate fingerprint, while the version and code hash change.

Composition input methods and keyboards that do not emit Fn events need separate hardware validation. A successful API call or a screenshot does not establish support.

For updater changes, use signed distribution builds and verify detection, cancellation, installation, preference persistence, offline errors and rejection of invalid signatures. Dev builds intentionally cannot install official updates.

See [release instructions](docs/releasing.md) for publishing.
