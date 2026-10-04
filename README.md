# OrbitShift

**Your languages. One key.**

A native macOS menu bar utility for cycling through keyboard input sources when you release a configurable key, without waiting for the standard input-source switcher.

> In development: requirements are defined; there is no runnable application or release yet.

## Planned features

- Switch once on key release, preserving shortcuts such as Fn + Delete.
- Choose a trigger key; Fn / Globe is the default.
- Add multiple macOS input sources, arrange them, and cycle through them in order.
- Start automatically when you sign in to macOS.
- Keep the standard macOS language indicator consistent with actual typed input.
- Follow input-source changes made outside OrbitShift.
- Check GitHub Releases automatically and install signed updates after confirmation, preserving settings.

## Requirements

[REQUIREMENTS.md](REQUIREMENTS.md) is the source of truth for behavior, edge cases, update delivery, and acceptance checks.

## Implementation

Swift, SwiftUI, AppKit, Text Input Source Services, ServiceManagement, and [Sparkle 2](https://sparkle-project.org/documentation/). Proposed minimum: macOS 14.

Build and installation instructions will be added with the first executable version.
