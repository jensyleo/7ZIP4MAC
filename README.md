# 7ZIP4MAC

A native macOS graphical interface for [7-Zip](https://www.7-zip.org/), built to
feel like a first-party Apple application. 7ZIP4MAC is a frontend only: it drives
the official, unmodified `7zz` engine, which is bundled inside the application.

> Status: **v1.0.0**

## Features

- **Open and browse** almost anything 7-Zip supports (7z, zip, tar, gz, bz2, xz,
  rar, iso, cab, cpio, arj, lzh, wim, rpm, deb, chm, and more) with hierarchical
  folder navigation, sortable columns, and real per-file-type icons.
- **Extract** the whole archive or a selection, with live progress
  (percent/speed/ETA) and cancellation.
- **Create archives** (7z / ZIP / TAR) with a chosen compression level, optional
  password + filename encryption, split volumes, and built-in or custom
  compression profiles.
- **Edit archives in place** — Add, Rename, Move, Copy and Delete entries inside
  an already-created archive, without a full re-compress.
- **Password-protected archives**: the password is asked for and kept only in
  memory for that session (never written to disk); the prompt caps out at 3
  attempts before resetting the window.
- **Drag entries out to Finder** or preview them in place with **Quick Look**
  (Space bar).
- **Test** an archive's integrity, run a **compression benchmark**, and browse
  recently opened archives.
- File-type associations (Settings ▸ File Types) to make 7ZIP4MAC the default
  handler for the formats it supports.
- AppleScript and Shortcuts/Siri automation (both off by default — enable in
  Settings ▸ Automation).

> **Note:** after associating a format (or uninstalling), Finder's icon for
> already-existing files of that type can take a while to refresh — that's
> Finder's own icon cache, not a broken association. Relaunching Finder
> (⌥-right-click its Dock icon ▸ Relaunch, or `killall Finder` in Terminal)
> usually fixes it; if it doesn't, restarting the Mac reliably clears it.

## Architecture

Strict MVVM with a clean separation between UI, logic and the engine:

```
SwiftUI Views  →  ArchiveViewModel  →  ArchiveService  →  SevenZipBridge  →  7zz
   (render)          (state)            (logic)          (process bridge)   (engine)
```

- **`SevenZipKit`** — a standalone, fully unit-tested Swift package containing the
  models (`Archive`, `ArchiveEntry`, `ProgressInfo`, `ExtractionRequest`,
  `CompressionRequest`, `ArchiveFormat`), the typed error type (`ArchiveError`),
  the process bridge (`SevenZipRunner`, `SevenZipBridge`), the `-slt` listing
  parser, the live progress parser/tracker, and the services. No UI dependency.
- **`App`** — the SwiftUI application. Views only render state and forward user
  intents; all logic lives in the ViewModel and the services.

The Views never call the engine directly. The engine is spawned in exactly one
place (`SevenZipRunner`), and standard output / standard error are drained
concurrently so a large listing can never deadlock a pipe. Long operations use a
streaming variant that parses the engine's live progress (`ProgressParser`) and
turns it into throughput/ETA (`ProgressTracker`), and can be cancelled — which
terminates the underlying process.

## The 7-Zip engine

The official `7zz` binary (universal, x86_64 + arm64) is bundled verbatim at
`Contents/Resources/Engine/7zz`. It is never modified. Its license is included
alongside it (`App/Resources/Engine/License.txt`). All compression, extraction,
encryption and archive reading is performed by this engine; the application only
provides the interface.

## Building

Requirements: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
# Run the core package tests
cd SevenZipKit && swift test

# Generate the project, build, sign (ad-hoc) and install the app
Scripts/build.sh
```

The app is installed to `/Applications/7ZIP4MAC.app`.

> Note: on a development machine the app is signed ad-hoc (`-`). A Developer ID
> signature is needed to distribute it without a Gatekeeper prompt on other
> machines.

## License

Application code: [GNU GPL v3.0](LICENSE) © 2026 Jensy Leonardo Martínez Cruz.
Bundled 7-Zip engine: GNU LGPL (with the unRAR restriction on commercial use of
the unRAR code), by Igor Pavlov — see `App/Resources/Engine/License.txt`.

This program is free software: you can redistribute it and/or modify it under the
terms of the **GNU General Public License, version 3**. It is distributed in the
hope that it will be useful, but **WITHOUT ANY WARRANTY**. See the [LICENSE](LICENSE)
file for the full text.
