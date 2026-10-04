# OrbitShift

**Your languages. One key.**

OrbitShift is a planned native macOS menu bar utility for cycling through keyboard input sources when you release a configurable key, without waiting for the standard input-source switcher.

> Status: project definition. This repository currently contains the first-version requirements and proposed design. There is no runnable application or release yet.

## Planned behavior

- **Switch on release.** A standalone press switches once when the key is released. Using the key in a shortcut, such as Fn + Delete, does not switch the language.
- **Choose your key.** Fn / Globe is the default; another key can be configured in Settings.
- **Cycle through your languages.** Choose multiple macOS input sources, set their order, and cycle through the list: English → Russian → German → English.
- **Start at login.** An optional macOS login item starts OrbitShift when you sign in.
- **Keep the system indicator correct.** Switching must update the actual system input source, the text being typed, and the standard macOS input-menu indicator consistently.
- **Follow external changes.** Changing the input source through macOS or another application becomes the starting point for the next cycle.

## Proposed implementation

A native Swift application with SwiftUI settings and AppKit integration. Input sources are managed through macOS Text Input Source Services; login registration uses ServiceManagement.

Keyboard handling must distinguish a standalone key press from a chord, handle key repeat, and recover after sleep or keyboard reconnection. The exact event-capture strategy will be validated on real hardware before it is treated as complete.

The standard macOS input indicator is an acceptance requirement, not a claim that has already been verified. End-to-end checks must compare the indicator with actual typed characters.

## Design

See [the first-version design](docs/superpowers/specs/2026-10-04-orbitshift-design.md) for the agreed requirements, proposed architecture, edge cases, and acceptance checks. The design is a draft for review.

## Development status

- Name and scope agreed.
- Public repository requested.
- Product design drafted; implementation has not started.
- Minimum macOS version proposed: macOS 14.
- Initial verification target: macOS 26.6.2 with U.S. and Russian input sources.

Build and installation instructions will be added when an executable version exists.
