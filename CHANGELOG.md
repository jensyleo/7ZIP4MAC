# Changelog

All notable changes to 7ZIP4MAC are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [1.7.30] — 2026-10-08

### Security
- Files extracted with 7-Zip now keep macOS's "downloaded from the internet" marker (`com.apple.quarantine`) when the archive has it, so Gatekeeper checks an app unpacked from a downloaded archive just as it would with the system's own unarchiver. 7-Zip itself never copied it. This covers Extract, dragging an item out to Finder, and archives unwrapped from `.gz`/`.bz2`/`.xz`. Files that were already in the destination folder are left untouched.
- Copy and Move now refuse a destination path that is absolute or contains `..`. The default destination comes from the entry's own name, which an archive controls.
- The Shortcuts "Compress" action ignores any directory part in the archive name, so the archive cannot be created outside its scratch folder.

### Internal
- Removed unused code (an unused icon-name table and two unused constants), shared the "trim trailing slash" helper instead of eight copies of the same expression, and fixed misplaced doc comments.
- Added tests for the quarantine marker (including real 7-Zip extractions) and for path validation.

## [1.7.29] — 2026-10-07

### Added
- Multi-part RAR sets (`name.partNN.rar`) with a 0-byte or missing volume can now be opened, listed, extracted and tested. 7-Zip refuses the whole set (or stops listing at the first gap); a bundled fallback (`lsar`/`unar` from The Unarchiver, LGPL-2.1-or-later, Apple Silicon only) reads each volume on its own, so everything outside the damaged volumes stays usable. It is used only for damaged sets; healthy archives still go through 7-Zip. Archives found inside the archive are not expanded, as with 7-Zip.
- Integrity test now shows live progress (percentage, current file, speed, time remaining) with a Cancel button, runs one test at a time, and lists each damaged file with its reason instead of a generic failure.
- Password prompt has a button to show or hide what is typed.

### Fixed
- The drag-out progress bar no longer jumps between items when several are dragged at once, no longer sits at 100% while the files are being moved into place, and shows speed and time remaining. Extract and Test now measure speed over the last few seconds, so the time remaining follows a slow network volume instead of staying optimistic.
- An extraction that finishes with some files missing now says everything else was extracted, and tells a write failure at the destination (dropped network connection, disk full) apart from damaged archive data.
- Entering the password of an archive whose contents (not its headers) are encrypted no longer re-reads the whole archive, which could take minutes on a network volume.
- At most two drag-out items extract at the same time, instead of every item at once.

### Security
- When a flattened selection is moved out of its scratch folder, anything reached through a symlink that points outside that folder is skipped, and old scratch folders left by an interrupted run are removed.

### Internal
- Removed dead code and duplicated line-buffering/escaping logic in the new fallback path; added unit and end-to-end tests (including symlink containment and nested-archive handling).

## [1.7.28] — 2026-09-22

### Fixed
- Dragging several entries out at once no longer flashes a separate progress panel (and steals focus) for each one — they now share a single panel for the whole drag.
- Cancelling a drag-out during a cross-volume move (external drive, network share) no longer leaves a completed duplicate at the destination.

### Internal
- Deduplicated three copies of the same recursive file-size calculation into a single shared helper.

## [1.7.27] — 2026-09-22

### Fixed
- The drag-out progress panel's bar now shows the normal blue accent color instead of gray — it needed to become the active/key window for AppKit to render it that way, and by the time it appears the drag gesture is already over, so that's safe to do.

## [1.7.26] — 2026-09-22

### Changed
- The floating progress panel shown while dragging an entry out to Finder now looks exactly like the one Extract's toolbar/menu action uses (same layout, percentage, speed/remaining/size, Cancel button) — shown one phase at a time (extracting, then moving into place) instead of a custom two-bar design.

## [1.7.25] — 2026-09-22

### Added
- Dragging an entry out to Finder now shows a small floating progress window with two bars: extraction, and the move into the destination. It never takes focus away from Finder. The move bar completes instantly for a same-disk drag (that step really is instant there) and shows real incremental progress when dragging to a different volume (external drive, network share).

## [1.7.24] — 2026-09-21

### Fixed
- Reverted last release's attempt at showing drag-out extraction progress in Finder's own UI — it didn't actually work, and couldn't: the extraction happens in a hidden, verified scratch location before an instant final move into place, so there was never anything visible for Finder to attach progress to. Extract Selected/Extract All remain the reliable way to see progress on a large item.

## [1.7.23] — 2026-09-21

### Fixed
- Dragging an entry out to Finder now reports real progress through Finder's own copy-progress UI while it extracts — previously there was no feedback at all for a large file during a drag (only the toolbar/menu Extract had a progress bar).

## [1.7.22] — 2026-09-21

### Added
- Adding files to an archive (toolbar Add…) and copying an entry within an archive now show the same progress bar (percentage, speed, ETA, cancel) that extraction already had, instead of no indication at all while a large file compresses.

## [1.7.21] — 2026-09-18

### Security
- Extracting, dragging out, or Quick Looking an entry that's a symlink pointing outside its own extracted contents is now refused, instead of Quick Look silently rendering whatever real file that link resolved to. 7-Zip already blocks most such symlinks itself; this closes the same gap as defense-in-depth.
- Tightened the dangerous-symlink tolerance added last release to match only 7-Zip's own fixed error prefix, not any line merely containing that phrase.

### Internal
- Deduplicated process-launch setup shared by the two ways the app runs the 7-Zip engine, and the now-identical error handling in Delete/Rename.

## [1.7.20] — 2026-09-18

### Fixed
- Double-clicking an archive while 7ZIP4MAC wasn't running no longer opens two windows (the archive and a stray empty one).
- Extracting, dragging out, or copying an entry that's a real macOS .app bundle (or any package with nested symlinked frameworks) no longer fails outright — 7-Zip's own safety check against unsafe symlink chains was being treated as a fatal error even when it had already done its job and skipped just the unsafe links.
- Dragging a directory entry recognized as a package (.app, .bundle, .framework, etc.) out to Finder now declares its real type instead of a generic folder, which Finder was silently refusing.

## [1.7.19] — 2026-09-17

### Security
- Fixed a low-impact path-traversal issue where a crafted entry name inside an opened archive could make the post-extraction "reveal in Finder" selection point outside the destination folder. Extraction itself was never affected — only which item Finder was told to select afterward.

### Internal
- Deduplicated the repeated error-message fallback logic (stderr, or stdout when empty) across the 7-Zip bridge's five operations into a single `ProcessResult.diagnosticMessage`.

## [1.7.18] — 2026-09-17

### Fixed
- Dragging out (or copying within an archive) an entry that lives inside a subfolder no longer recreates its whole ancestor folder chain at the destination — it drops just the item itself, where you told it to.

## [1.7.17] — 2026-09-16

### Security
- Fixed a path-traversal issue where a crafted entry name inside an opened archive (e.g. "../../../../Users/me/.ssh/id_rsa") could make drag-out or in-archive "Copy…" resolve to a real file elsewhere on disk instead of the extracted entry, and then move it — silently relocating or exfiltrating a file the user never intended to touch. Both operations now verify the actual extracted item instead of trusting the entry's name.

### Internal
- Removed a dead error-handling branch and deduplicated a repeated file-existence check in the 7-Zip bridge.

## [1.7.16] — 2026-09-16

### Fixed
- Cmd-clicking a row to add it to an existing selection, then extending with Shift or Cmd+Shift+Arrow, no longer drops the rows that were already selected — the extension now unions with what was there instead of replacing it.

## [1.7.15] — 2026-09-16

### Fixed
- Shift+Arrow now correctly grows the range selection one row at a time instead of getting stuck after the first row.
- Added Cmd+Shift+Up/Down to extend the selection to the first/last item, matching Finder.
- The ".." (go up) row can no longer end up inside a keyboard-driven selection range.

## [1.7.14] — 2026-09-16

### Security
- Sanitize Shortcuts-supplied filenames in the Compress/Extract App Intents (lastPathComponent), closing a path-traversal vector in the Shortcuts/Siri integration.

### Fixed
- Toolbar icons are noticeably larger again (pointSize 19), per user feedback.

### Internal
- Removed duplicated Shift-click/Shift-arrow range-selection logic in the file list behind a shared helper.

## [1.7.13] — 2026-09-16

### Fix

**Fixed: disabled toolbar icons flickering to full brightness**

Confirmed with screen recordings and diagnostic instrumentation: this app's interface redraws at a constant ~60 times per second in the background (present since much earlier versions, not new). `NSToolbarItem` computes a disabled icon's dimmed appearance dynamically on every redraw, and that computation intermittently dropped out at this rate — briefly showing the full-color "enabled" artwork before correcting itself, regardless of mouse movement.

The disabled look is now baked directly into a pre-dimmed image (cached, can't flicker) instead of relying on `NSToolbarItem`'s own dynamic dimming. Disabled buttons still do nothing when clicked; the only visible difference is they now show the normal hover highlight.

## [1.7.12] — 2026-09-15

### Fix

**Fixed toolbar icons flickering right on launch** — toolbar symbols had no explicit size/weight configuration, so the system rendered them provisionally during the toolbar's early layout, then re-rendered once its real sizing context settled — visible as a brief flicker across every icon right when the app opens. Every toolbar icon now gets a fixed configuration up front, stable from its very first frame.

## [1.7.11] — 2026-09-15

### Fixes

**"." now acts on a single click** — it reads as a button (a back-arrow icon, no real name), not a row you select then double-click, so one click now goes up a folder immediately. Its icon is also slightly larger.

**Fixed icon flicker on hover** — every file-type icon flickered when the cursor passed over its row. Icons are now resized to their real 16×16 display size once, at cache time, instead of being rescaled from a large system image on every redraw.

## [1.7.10] — 2026-09-15

### Bug Fix

**Fixed: tiny click area on short row names, especially ".." (go up a folder)**

Each row's Name cell stretched visually across the whole column, but only the actual icon+text counted as clickable — nearly invisible for a long file name, but the "." row (icon + two characters) left most of the row unclickable, matching what was reported. The whole stretched row area is now clickable, not just where something is drawn.

## [1.7.9] — 2026-09-15

### New Feature

**Arrow-key navigation in the file list**

- ↑/↓ move the selection one row at a time (Shift extends a range), same as Finder's List view
- → enters the selected folder, ← goes up a level, same as Windows Explorer / 7-Zip's own file list
- No selection yet: ↓ starts at the first row, ↑ starts at the last row

## [1.7.8] — 2026-09-13

### Bug Fix

**Fixed: window appeared to lag when opening an archive**

When the app was already running and a file was opened (Finder double-click, Open Recent, drag-to-Dock), macOS creates an extra empty scaffold window alongside the one that actually loads the file. The logic meant to hide that empty window had a timing race — it often failed to hide it, so users would briefly see a blank "No Archive Open" window before the real content appeared on top of it. This read as the app being slow, even though the actual archive listing completes in single-digit milliseconds.

Fixed by tracking window order deterministically instead of checking window count at an arbitrary instant. Verified with screen-capture sequences: the empty window no longer appears at all when opening a file with the app already running.

## [1.7.7] — 2026-09-13

### Security & Code Audit

Full-codebase audit — dead code, duplication, and security review (not just recent changes).

### Security fixes
- **Argument injection via entry names**: an archive entry named e.g. `-weird.txt` could be misread by the bundled 7-Zip engine as a command-line flag instead of a file name, confirmed with a real test case. Every operation that passes entry/file names to the engine (Extract, Test, Delete, Move, Add/Compress) now correctly separates them from its own flags.
- **Silent format fallback in automation**: Shortcuts/AppleScript compress commands to an unrecognized destination extension silently produced 7z content under a misleading filename instead of failing — now fails with a clear error.
- Documented a known, unavoidable limitation (password briefly visible in the process list while the engine runs) in SECURITY.md.

### Cleanup
- Removed 4 duplicated temp-directory-creation snippets, 6 duplicated error-message fallbacks, and a duplicated AppleScript command dispatch pattern — same behavior, less code to maintain.
- Fixed an avoidable O(n·m) selection-filtering pass in Extract.

No dead code found. All 46 automated tests pass; verified against real .zip and .tar.bz2 archives after the refactor.

## [1.7.6] — 2026-09-13

### Bug Fix (follow-up to v1.7.5)

v1.7.5 fixed `.tar.bz2` showing empty, but the detection only triggered when the archive listed zero entries — which missed `.tar.gz`: gzip embeds the original filename in its header, so it already listed one entry (the `.tar` itself, unopened) instead of zero, looking superficially fine while still not being browsable.

The unwrap now triggers purely off the archive's format (bzip2/gzip/xz/lzma/z/brotli/lz4/lz5), not off whether it already reports an entry. Verified against `.tar.gz`, `.tar.bz2`, and `.tar.xz` — all now list their real contents — and a standalone `notes.txt.gz` with no tar inside, which correctly falls back to gzip's own single-entry listing (real name and size from its header) instead of losing it.

## [1.7.5] — 2026-09-13

### Bug Fix
- **Fixed: `.tar.bz2`/`.tar.gz`/`.tar.xz` archives showed empty when opened**

bzip2/gzip/xz are single-stream compressors with no entry list of their own — opening a bare `.tar.bz2` reported zero entries because the compressed stream itself isn't a container, only what's inside it (usually a `.tar`) is. The app now transparently unwraps this single stream and lists the real archive inside, so browsing, extracting, Quick Look, and drag-to-Finder all work as expected.

In-place editing (Delete/Move) is explicitly disabled for this kind of archive, since there's nothing sensible to write changes back into — an accurate limitation rather than a silent failure.

## [1.7.4] — 2026-09-07

### New Features
- **Help menu**: Professional-grade searchable help system with 10 comprehensive topics
  - Keyboard Shortcuts, Opening/Browsing, Extracting, Creating, Editing archives
  - Encrypted archives, Testing, Toolbar customization, Settings

### Implementation
- HelpTopic.swift: Topic definitions with sections, paragraphs, and term-detail rows
- HelpView.swift: NavigationSplitView-based interface with real-time search
- Integrated into app menu via CommandGroup(replacing: .help)

The help system is searchable, fully documented, and accessible via Help menu.

## [1.7.3] — 2026-08-26

Bug fixes and hardening from code review:

- **Quick Look**: Fixed potential array out-of-bounds crash on concurrent access by adding bounds checking
- **Drag staging**: Increased sweep age from 1 hour to 24 hours to prevent race condition where cleanup could interrupt active Finder drags
- **Archive parsing**: Added null-byte validation to reject malformed entry paths in archives
- **46/46 tests passing**, no regressions

## [1.7.2] — 2026-08-25

Adds a **Close** button to the Benchmark window, next to Run Again, so you can dismiss the results without reaching for the window's title bar.

## [1.7.1] — 2026-08-25

Bug fixes and hardening for v1.7.0's toolbar customization:

- Fixed a bug where, with more than one window open, a window that hadn't been touched since launch could silently overwrite another window's just-completed manual toolbar reorder on its next unrelated render (a selection change, folder navigation, etc.). Toolbar order is now only persisted in direct response to a real user reorder.
- Toolbar icons are now cached instead of rebuilt on every render, reducing unnecessary work during extraction progress updates and other frequent UI refreshes.

No user-facing behavior changes beyond the fix — this is a follow-up debugging/hardening pass after a security and code review of v1.7.0.

## [1.7.0] — 2026-08-25

**Toolbar customization is back** — right-click (or ⌘-drag) the toolbar to reorder items or switch between icon+text/icon-only/text-only, with your layout remembered across launches.

Previously reverted in v1.6.1 after a crash: SwiftUI's declarative `.toolbar(id:)` API turned out to be unsafe with multiple windows sharing a toolbar identifier on macOS 26.6.2. This release replaces it with a hand-built `NSToolbar` bridged into the SwiftUI view — each window owns its own real AppKit toolbar, sidestepping SwiftUI's cross-window layout restoration entirely.

Verified live with two windows open simultaneously — no crash, native Customize Toolbar sheet works as expected.

Also includes the v1.6.2 fix for GNU tar archives showing no contents.

## [1.6.2] — 2026-08-24

Fix GNU tar display: tar archives now show all files correctly (strips ./ prefix and drops bare . root entry). Builds on recent QuickLook multi-window fixes and toolbar stability improvements.

## [1.6.1] — 2026-08-24

### Critical Fix

v1.6.0 introduced a crash that occurred every time a file was opened while the app was already running (e.g. double-clicking a .zip/.7z in Finder). Root cause: the customizable toolbar feature (`.toolbar(id:)`) hit an AppKit bug on macOS 26.6.2 when a second window was created, unrelated to any saved preferences.

**Reverted the toolbar customization feature entirely** to restore stability. The toolbar is back to its non-customizable v1.5.0 form.

Quick Look fixes from v1.6.0 are retained:
- Fixed Quick Look randomly failing when clicking files while panel is open
- Space/⌘Y toggle behavior (close if open, else open), matching Finder
- Auto-refresh preview when selection changes
- Fixed responder chain truncation bug

## [1.6.0] — 2026-08-24

### Changes

**Quick Look Fixes**
- Fixed Quick Look randomly failing when clicking files while panel is open — now properly implements the QLPreviewPanel controller protocol to hand control between windows
- Space bar and ⌘Y now toggle Quick Look (close if open, else open), matching Finder behavior
- Clicking a different file while Quick Look is open now refreshes the preview instead of leaving stale content
- Auto-closes Quick Look if selection is cleared or narrowed to folders only

**Toolbar Customization**
- All toolbar buttons now support native macOS customization: right-click toolbar → "Customize Toolbar…"
- Toolbar configuration persists across app launches

**Code Fixes**
- Fixed responder chain management: no longer truncates window.nextResponder when inserting Quick Look controller
- Deferred responder chain assignment to avoid AppKit initialization crash

**Security Audit**
- Comprehensive security review: no command-injection or path-traversal vulnerabilities found
- Architecture (array-based subprocess arguments, delegating path writes to real 7z binary) safely avoids injection pitfalls
- Known trade-off: passwords passed as CLI arguments on multi-user systems may be visible via `ps` during extraction—this is a known limitation in most 7z GUI wrappers (7z CLI doesn't support password-via-stdin cleanly)

## [1.5.0] — 2026-08-11

### New Features
- **Multi-window support**: Each archive opens as an independent window, just like Preview or TextEdit
- **Cross-archive drag-and-drop**: Copy or move files between two open 7-Zip archives by dragging
- **Rename option in conflicts**: When dragging files with name collisions, choose to Overwrite, Skip, or Rename with automatic collision detection
- **Data-loss prevention**: Move operations now safely verify the destination add succeeds before deleting from source

### Improvements
- Fixed silent duplicate-name bug when renaming files within an archive
- Added collision re-validation when manually entering renamed names
- Removed unused cross-archive transfer metadata field
- Eliminated all compiler warnings (0 warnings in Release build)

### Bug Fixes
- Fixed Shift/Click and Cmd/Click multi-selection regression from drag-overlay changes
- Corrected alert timing issue when rapidly rejecting duplicate names
- Fixed pattern-matching condition that only applied to one delete-key variant

## [1.4.0] — 2026-07-17

### Added
- Dragging several selected entries out to Finder now delivers each one as
  a separate file, exactly like dragging a single entry — replacing the
  previous release's "one folder" behavior.

### Note
Double-clicking an entry that's already part of a larger selection isn't a
supported gesture — click it alone first, then double-click normally.

## [1.3.0] — 2026-07-17

### Added
- Dragging several selected entries out to Finder at once now brings all of
  them along, delivered inside one folder. (Improved further in the next
  release — see v1.4.0.)

## [1.2.2] — 2026-07-17

### Added
- ⌘A (Select All) in the file list.

## [1.2.1] — 2026-07-16

### Fixed
- The "Extraction Complete" dialog now always appears when the overwrite
  policy isn't Overwrite, and states exactly what happened — which existing
  files were left untouched (Skip), or that the newly extracted file was
  renamed instead (Rename Extracted File).

## [1.2.0] — 2026-07-15

### Added
- Extraction overwrite policy is now configurable (Settings ▸ General):
  Overwrite, Skip, or Rename Extracted File.
- Quick Look (Space) now previews every selected file, with arrow-through
  navigation between them, instead of just the first.

## [1.1.0] — 2026-07-15

### Fixed
- Opening a file from Finder while the app was already running no longer
  opens a duplicate window — it uses the window already open.
- Uninstalling now properly hands back any file-type associations to
  whatever app opened them before, instead of leaving them pointing at the
  deleted app.
- The password prompt's Cancel/Escape and the 3-attempt limit now reset the
  window to its empty state instead of quitting the app, and it always
  shows how many attempts are left.

### Added
- "Associate Recommended Files…" button in Settings ▸ File Types, to
  associate the common formats in one action. The app also points you to
  this tab the first time you launch it.
- A note that a stale Finder icon after associating/uninstalling a format
  is just Finder's own icon cache, not a broken association.

## [1.0.0] — 2026-07-11

First public release.

### Added
- **The password prompt now has a 3-attempt limit and always shows the
  count.** Previously, cancelling (or pressing Escape — same action) just
  dismissed the sheet, and there was no cap on wrong-password retries; both
  invited confusing half-open states. Now: the prompt always states "You
  have 3 attempts", each wrong password shows how many are left, and
  cancelling/Escape/hitting the limit all reset the app to its empty state
  (as if freshly launched) instead of leaving an archive loaded-but-locked
  underneath.

### Removed
- **Keychain integration.** Encrypted archives still prompt for a password
  to open, but it's no longer saved anywhere — it's kept in memory only for
  the current session (so Add/Delete/Move/Copy on an already-open encrypted
  archive don't re-prompt for every action), and is gone the moment the
  archive is closed or the app quits. Removed: `KeychainService`, the
  "Remember password in Keychain" toggles (both in the New Archive sheet and
  the unlock prompt), and the Keychain cleanup step in the uninstaller.
  KeePass support (the planned Phase 7 — a pluggable password-provider
  abstraction with a KeePass backend) is dropped from the roadmap along with
  it, since it was meant to plug into the same password-storage layer.
- **All Finder integration — the Finder Sync extension, the
  `sevenzip4mac://` URL scheme, "Compress with 7ZIP4MAC", and the older
  "7ZIP4MAC ▸ Compress…/Extract" submenu.** Root cause: Finder Sync
  extensions require a paid Apple Developer ID code signature to be
  accepted by macOS at all (verified directly: `pluginkit` refused to
  recognize the extension no matter how it was registered/enabled/reset,
  even though LaunchServices' own bundle scanner saw it fine — a stricter,
  separate validation gate that ad-hoc signing can't pass). Since this
  project doesn't have a paid Developer ID, none of it could ever actually
  work — including, in all likelihood, the original "Compress…/Extract"
  submenu from Phase 3, which had only ever been verified by firing its URL
  scheme directly rather than through a real Finder menu. Removed the
  `FinderExtension` target/folder entirely, the URL-scheme routing in
  `AppURLRouter`/`ContentView` (now just handles opening a file), and the
  now-unused `ArchiveViewModel.openThenExtract`/
  `CompressionViewModel.beginQuickCompress`. Also unregistered the leftover
  `.appex` from `pluginkit`/LaunchServices on this machine.

### Fixed
- **Extracting from an archive that encrypts only entry *content* (not
  names/headers) could fail with "The 7-Zip engine reported an error (code
  255): Break signaled".** Such archives list successfully without ever
  needing a password (7-Zip only asks once it has to decrypt actual bytes),
  so the app never prompted and `sessionPassword` stayed `nil`; the first
  Extract/Add/etc. then ran with no password at all, and the engine fell
  back to an interactive prompt that hung against our closed stdin. Fixed:
  after opening an archive without a password, if any entry is actually
  encrypted (`Encrypted = +` in the listing), the password prompt now shows
  proactively — the archive stays loaded and browsable underneath, so
  cancelling just means "browse only, don't extract yet."
- **Dragging a plain-text entry (`.txt` or any other `public.plain-text`-
  conforming type) out of an archive to Finder silently did nothing** (drop
  rejected, snap-back animation, no file delivered), while the exact same
  drag worked for extensionless entries, `.docx`, and other non-text types.
  Root cause: the file promise was registered under the entry's real UTI, and
  for text-conforming types Finder treats the drop as a "text clipping"
  request instead of accepting the file promise — our promise's completion
  handler was simply never invoked. An earlier, unrelated Finder/pasteboard
  daemon glitch (fixed by an OS reboot, not by app changes) had briefly
  masked this as "drag-out doesn't work at all," delaying the real diagnosis.
  Fixed by registering text-conforming entries under the generic
  `UTType.data` identifier instead — Finder then accepts the promise
  normally and still names the delivered file correctly. Also:
  `SevenZipBridge.extract` no longer passes a bare `-p` (empty password),
  which could make the engine hang on an interactive prompt — the same guard
  the `d`/`rn` commands already had. Staging temp folders are swept on
  launch.
- **Quick Look and drag-out never worked on an encrypted archive's
  entries** — both hardcoded `password: nil` when extracting the entry to
  preview/drag, instead of using the password the archive was opened with.
  Now both reuse `ArchiveViewModel.sessionPassword` (the same in-memory
  password Add/Delete/Move/Copy already reuse), so previewing or
  dragging out an entry from a password-protected archive actually works.
- Quick Look (Space) and Rename (Return) could intermittently stop
  responding to their keyboard shortcut — most noticeably right after
  opening the Inspector, whose `.textSelection(.enabled)` fields are
  focusable and can steal keyboard focus away from the file list, silently
  breaking SwiftUI's focus-dependent `.onKeyPress`. Fixed the same way
  Delete/Backspace already was: a local `NSEvent` monitor that intercepts
  the key before focus-based dispatch, unaffected by which view currently
  has focus.
- Extract didn't filter out the ".." ("go up a folder") row from the
  selection like Test/Delete already did — selecting it and hitting Extract
  would have asked the engine to extract a nonexistent ".." path. Found in a
  debug/optimization pass over `ContentView.swift`.
- Uninstalling didn't revert file associations to the system default
  (Archive Utility) if any other copy of the app happened to exist anywhere
  on disk (e.g. a leftover dev build) — LaunchServices would silently latch
  onto that stray copy as the new default handler instead, since the
  uninstaller trashed the app without ever unregistering it from
  LaunchServices. Verified for real: ran the full uninstall (TCC reset,
  prefs/caches/saved-state removal, trash) with a second copy of the app
  present on disk — before the fix, `.zip`/`.7z` silently became handled by
  that stray copy; after adding an explicit `lsregister -u` step before
  trashing, they correctly fell back to Archive Utility every time,
  regardless of what else was lying around. Also confirmed no orphaned
  preferences, caches, or saved state remain after uninstalling.

### Removed
- The deferred "Windows-like visual identity" idea (toolbar/action icons
  styled like 7-Zip for Windows) is dropped from the roadmap entirely — the
  app keeps its native macOS look (SF Symbols throughout) with no plan to
  revisit this.

### Changed
- Move's toolbar/context-menu icon changed from `folder` (identical to
  Open's icon, confusingly) to `arrow.turn.up.right`.
- **Add/Rename/Move/Copy/Delete are now direct toolbar buttons**, not tucked
  into an "Edit" dropdown menu — one click instead of two. All of them fit
  on a single toolbar row; the toolbar's own overflow chevron would kick in
  automatically if the window got too narrow to show them all.

### Added
- **macOS-standard keyboard shortcuts** in the file list: **Return** renames
  the selected item (matching Finder's actual convention — Return renames,
  it doesn't open) and **Delete/Backspace** deletes the selection (with the
  existing confirmation). Double-click still opens, unchanged. (An earlier
  pass also added ⌘↓ to open the selection and used `.onKeyPress` for
  Delete; ⌘↓ was dropped as unnecessary, and Delete didn't actually work —
  `Table` swallows that key before SwiftUI's `.onKeyPress` sees it — so it's
  now backed by a local `NSEvent` monitor instead.)
- **Compression profiles: create and view details** from Preferences ▸
  Profiles — a "New Profile…" button and a tap-to-open editor for every
  profile (format, compression level, split size, password-required,
  encrypt-file-names). Built-in profiles open read-only (their fields
  disabled, no Save/Delete — you can see exactly what they do, but can't
  break them); custom profiles are fully editable and save in place even
  if renamed. Previously the only way to create a profile was via "Save
  these settings as a profile…" mid-compression, and there was no way to
  inspect a profile beyond its one-line summary.
- **Add files/folders into an existing archive**, from the toolbar "Edit"
  menu and the file list's right-click menu (`tray.and.arrow.down` icon) —
  reuses `compress`, which appends when the destination archive already
  exists. Verified against the real engine.
- **Dropping a file onto the window while an archive is already open** now
  asks what to do — add it into the open archive, or open it instead (only
  offered for a single dropped item) — instead of silently assuming "open
  this as a new archive," which made it impossible to drop something in to
  add it.
- **Add always landed items at the archive's root**, ignoring whatever
  folder you were browsing (or had dropped the file onto) inside the
  archive. `7zz a` takes an item's archive path from its path relative to
  the working directory, with no "add under this internal folder" option,
  so Add now stages each source into a scratch copy that mirrors the
  current folder before compressing — added files now land exactly where
  you were browsing. Verified against the real engine (adding into a nested
  folder preserved the rest of the archive and placed the new file at the
  right path).
- **Add and Copy silently did nothing (or could corrupt the archive) for any
  format other than .7z/.zip/.tar**: both guessed the container format from
  the archive's file extension and fell back to forcing `-t7z` when nothing
  matched — for a RAR, ISO, GZip, or any of the ~30 other formats this app
  can *open* but not *write*, that meant running `7zz a -t7z` against a file
  that isn't actually a 7z archive. Fixed: the format must now match
  exactly, or Add/Copy fail immediately with a clear message naming the
  archive's real format and explaining only .7z/.zip/.tar can be modified in
  place. Covered by a new integration test against the real engine.
- **Test** is now also in the toolbar's "Edit" menu (it already had its own
  dedicated toolbar button and was in the context menu; now all three
  places offer it consistently).
- Every Edit-menu and context-menu action now has a proper SF Symbol icon
  instead of text only: Rename (`pencil`), Move (`folder`), Copy
  (`doc.on.doc`), Delete (`trash`), Add (`tray.and.arrow.down`), Extract
  (`arrow.up.bin`), Test (`checkmark.seal`), Copy Name/Path, Quick Look.
- New Archive's toolbar icon changed from a generic "+" to `doc.zipper` —
  the plus didn't read as "create an archive" at a glance.
- **Edit an archive in place — Rename, Move, Copy and Delete** entries within an
  already-created archive, from a new toolbar "Edit" menu and the file
  list's right-click menu:
  - **Delete** (`7zz d`) removes the selected entries, with a confirmation
    alert first.
  - **Rename** (`7zz rn`) prompts only for a new name, keeping the entry in
    its current folder — matching Finder's "Rename".
  - **Move** (also `7zz rn`) prompts for a full new path, so it can relocate
    an entry into a different folder within the archive.
  - **Copy** has no native "copy within archive" 7z command, so it's built
    from what does exist: extract the entry to a scratch folder, restage it
    under the new path, then append it back into the same archive.
  All three re-list the archive afterwards so the file list reflects the
  change immediately. Verified against the real bundled engine (delete,
  rename, and the extract-then-append copy path all confirmed with real
  files before wiring into the UI).
  The post-extraction completion dialog (with its "Show in Finder" button) is
  now a Preferences ▸ General ▸ Extraction toggle ("Show a dialog when
  extraction finishes"), **off by default** — extraction otherwise just
  finishes quietly. Errors always show regardless.

  The "it worked" confirmation for Add/Delete/Move/Copy is now **four
  independent** Preferences ▸ General ▸ Notifications toggles, each off by
  default — turning one on doesn't affect the others. **Test always
  confirms** and isn't configurable: unlike the edit actions, its result
  isn't reflected anywhere else in the UI, so silencing it would hide the
  only signal it ran at all. Errors always show regardless of these toggles.
  Note: the toolbar/icon "Windows 7-Zip" visual identity idea was dropped —
  the toolbar keeps macOS-native SF Symbols throughout, including these new
  actions. An "Add" action (append arbitrary files into an existing archive)
  was scoped out of this pass, left for later.
- **Phase 6 automation — AppleScript and Shortcuts/Siri (App Intents)**,
  sharing one headless `AutomationService` (independent of the UI view
  models, since automation runs without a visible window). Both are **off
  by default** — a new Settings ▸ Automation tab has a toggle for each,
  since either one opens a way to compress/extract without any visible
  window:
  - **AppleScript**: a `7ZIP4MAC.sdef` dictionary exposes `compress` and
    `extract` commands (e.g. `tell application "7ZIP4MAC" to compress
    POSIX file "…" to POSIX file "…"`), backed by `NSScriptCommand`
    subclasses. Verified end-to-end via `osascript` against real files,
    including that it's refused with a clear error until enabled.
  - **Shortcuts / Siri (App Intents)**: `Compress Files` and `Extract
    Archive` actions, with ready-made shortcut phrases via
    `AppShortcutsProvider`. Shortcuts hands files in as in-memory
    `IntentFile`s (not live paths), so each intent stages them to a scratch
    directory, runs the same engine call, and returns the result as a file.
  - A Spotlight importer (indexing archive contents for ⌘Space search) was
    prototyped and then removed — not worth the added surface for now.
- **File Types** preferences tab: associate 7ZIP4MAC as the default opener
  for all 36 archive/disk-image formats, including 7z (mirrors 7-Zip for
  Windows' "System" options), grouped and color-coded to match the file-type
  icons (blue = common, orange = less common, yellow = disk images).
  "Associate All" and per-format toggles. All formats default on except
  ISO/DMG/PKG, which default off since associating them overrides macOS's
  built-in mount/install behavior. Association only happens when the user
  explicitly acts (never automatically on launch): macOS shows a
  confirmation dialog per format, so proactively firing them all on first
  launch would ambush the user with a stack of system dialogs.
  Note: a format's custom document icon in Finder only appears once
  7ZIP4MAC is its default handler (for macOS-owned types like .zip/.rar);
  Finder may need a relaunch to refresh already-cached icons.

### Changed
- New app icon, designed by the owner (`Icons/app_icon_1024.png`).
- **Every archive/disk-image format now has its own document icon** (all 36,
  designed by the owner — color-coded blue/orange/yellow by common/rare/
  disk-image), instead of one shared generic icon. Verified for real: asked
  macOS for the icon of an actual `.arj` file on disk and got the correct
  custom artwork back.

### Fixed
- Extracting a single selected **file** created up to two unwanted
  subfolders: the "wrap in a folder named after the archive" preference
  (meant for whole-archive/folder extraction) was applying to single files
  too, and the file's internal archive path (e.g. `docs/report.pdf`) was
  being recreated on disk even for a single-file extraction. Now: the
  archive-name subfolder only wraps whole-archive/folder extractions, and
  extracting only file(s) extracts flat (`7zz e` instead of `x`) straight
  to the chosen destination, with no subfolders at all — extracting a
  folder still preserves its internal structure, as expected.
- Extracting a **selected folder** still added the archive-name wrapper
  subfolder around it (e.g. `dest/ArchiveName/mydocs/…`), an extra level the
  folder doesn't need — it's already its own container. That wrapper is now
  reserved for whole-archive extraction only; a selected folder extracts
  straight to the destination (`dest/mydocs/…`).
- "Show in Finder" after extracting a single file revealed the *destination
  folder itself* instead of the extracted file, which looked like Finder
  jumping one level up the hierarchy (it was selecting the folder from
  inside its parent, rather than opening into it and selecting the file).
  Fixed by revealing the actual extracted item(s) at their recreated
  location, separately from the destination folder extraction ran into.
- Extraction both auto-opened Finder *and* popped a completion dialog whose
  "Show in Finder" button did the same thing — redundant. Extraction no
  longer auto-reveals; the completion dialog (now itself optional, see
  below) is the only place that opens the result. ("Reveal in Finder when
  finished" now applies to newly created archives only.)
- Delete/Move (`7zz d`/`rn`) failed with "The 7-Zip engine reported an error
  (code 255): Break signaled" on non-password-protected archives: a bare
  `-p` (no password characters attached) makes those two commands block
  waiting for an interactive password prompt instead of treating it as "no
  password" — unlike list/extract/test, which don't need to touch the
  password machinery for an unencrypted archive. With no terminal attached,
  that wait errors out. Fixed by only passing `-p<password>` when there
  actually is one.
- ⌘W didn't close the focused window when more than one window was open:
  the "Close Archive" menu item had claimed the standard ⌘W "Close Window"
  shortcut for an action tied to a single shared view model, conflicting
  with the system's per-window close. ⌘W now closes windows normally again;
  "Close Archive" is still in the menu, without a shortcut.
- The 7ZIP4MAC icon shown in Finder's "Open With" submenu could look stale
  after repeated reinstalls to the same path — a deeper icon cache
  (IconServices, not just Finder's own cache) needed a refresh.
- Double-click was occasionally missed ("a veces falla"): replaced
  `NSEvent.clickCount`-based detection (raced SwiftUI's event dispatch) with
  a deterministic timer using the user's own configured
  `NSEvent.doubleClickInterval`.
- Sorting by "Name" didn't reorder rows: the column was sorting by each
  entry's full internal path instead of its displayed name. Now sorts by name.

### Added
- **Every archive/disk-image format the bundled engine supports** is now
  declared as an openable document type (Finder "Open With" + the Open
  panel): 7z, ZIP, TAR, GZIP, BZIP2, RAR (read-only, per the engine's unRAR
  license terms — already bundled, no new licensing obligation), ISO, UDF,
  CAB, CPIO, XZ, Z, XAR, PKG/XIP, DMG, ARJ, LZH, WIM, RPM, DEB, CHM, NSIS,
  LZMA, ar, SquashFS, ext2/3/4, FAT, NTFS, HFS+, APFS, VHD/VHDX, VMDK, QCOW,
  VDI. The engine already read all of these; formats without a stable system
  UTType now have their own exported type declaration (`com.jensyleo.sevenzip4mac.*`) so Finder still recognizes them. Excluded on purpose: raw
  executables/partition tables (PE/ELF/Mach-O/GPT/MBR) and office-document
  containers (doc/xls/ppt) — not "archives" a user browses, and claiming them
  would be confusing. Verified end-to-end with a real ISO (created via
  `hdiutil`) and confirmed the new types register correctly with LaunchServices.
- **Hidden entries filter**: dotfiles and zip-tool artifacts (`.DS_Store`,
  `.git`, `__MACOSX`, …) are hidden by default when browsing an archive.
  Toggle in Preferences ▸ General ▸ Browsing ▸ "Show hidden items".
- **Test a selection**: the Test action (toolbar and context menu) now tests
  just the selected entries when something is selected, instead of always
  testing the whole archive.
- A **".."** row appears at the top of the list when browsing inside a
  folder (Windows Explorer / 7-Zip-for-Windows convention); double-click or
  Enter it to go up one level.
- **Hierarchical navigation** (Phase 4): browse inside archives folder by
  folder with a breadcrumb bar, an Up button, and double-click / Return to
  enter a folder — instead of a flat path list.
- **Test archive** action (`7zz t`) with a pass/fail result.
- **Real file-type icons** for entries (via macOS/UTType), and a branded
  document icon so Finder shows a 7ZIP4MAC icon on archives it owns.
- The app now installs to `/Applications` and no longer registers twice in
  Finder / "Open With".
- **About** and **Help** menu items
  (standard About panel with 7-Zip license credits; a quick-reference Help alert).
- **Inspector** panel (⌘⌥I-style toggle in the toolbar): full detail for the
  selected entry — path, attributes, sizes/ratio, modified date, CRC, method,
  encryption. Closed by default.
- Folder and encrypted-entry names are tinted in the file list (a lightweight
  row-status convention).
- **Right-click context menu** on entries: Quick Look, Extract…, Copy Name,
  Copy Path.
- Fixed unreliable row selection / double-click in the file list: clicks are
  now handled explicitly (via the real click count and modifier keys) instead
  of racing a custom gesture against the table's own, per user testing
  feedback (2026-07-09).
- **Standard multi-select**: ⌘-click toggles a row in/out of the selection,
  Shift-click selects a contiguous range from the last-clicked row — matching
  macOS/Windows conventions.
- The breadcrumb bar now tints clickable segments with the accent color so
  it reads clearly as navigable, matching Finder's path bar.
- The bundled engine reference is now resolved once and cached instead of
  re-validated on every single operation.
- **Single-instance enforcement**: launching the app while it's already
  running activates the existing window instead of opening a second one.
- **Uninstall 7ZIP4MAC…** (toolbar ▸ More): removes preferences, caches,
  Keychain-saved archive passwords, disables the Finder extension, and moves
  the app to the Trash.

- **Benchmark** (Phase 3): a Tools ▸ Benchmark window (⇧⌘B) runs the engine's
  `7zz b` and shows compress / decompress / total MIPS ratings, machine info,
  and a per-dictionary-size table.
- **Compression profiles** (Phase 3): built-in presets (Ultra, Fast Backup,
  Encrypted, Source Code, Photos, Split DVD) plus user-saved profiles, chosen
  from a Profile picker in the New Archive sheet and managed in
  Preferences ▸ Profiles.
- **Split into volumes**: create multi-part archives (CD / FAT32 / DVD / custom
  sizes) via `7zz -v`; opening the first part reads the whole archive.
- **Recent archives**: recently opened archives appear in the empty-state
  window and in File ▸ Open Recent (with Clear Menu); missing files are hidden.
- **Advanced encryption** (Phase 3): opening an encrypted archive now shows an
  unlock prompt; passwords can be saved to the macOS Keychain and are filled in
  automatically next time. New archives offer "Remember password in Keychain".

## [0.4.0] — 2026-07-08

### Added
- **Finder extension**: a Finder Sync extension adds a *7ZIP4MAC ▸ Compress… /
  Extract* submenu to the right-click menu. It hands the selected paths to the
  app via the private `sevenzip4mac://` URL scheme.
- **Custom URL scheme & document types**: the app now handles
  `sevenzip4mac://compress` / `sevenzip4mac://extract` and opening archive files
  directly (double-click / *Open With*).
- **Quick Look**: preview the selected entry in place with the Space bar or the
  toolbar button; the entry is extracted to a temporary file on demand.
- **Drag out to Finder**: drag an entry from the list to Finder to extract it
  lazily (a file promise — nothing is written unless dropped).
- **Preferences** (⌘,): default archive format, compression level and
  file-name encryption; extract-into-subfolder and reveal-in-Finder behaviour.
- Integration test suite exercising the real `7zz` engine (compression
  round-trips, whole/selected/folder extraction, encrypted headers).

### Changed
- Bumped marketing version to 0.4.0.
- The CRC column is more legible on selected rows.

## [0.3.0] — 2026-07-08

### Added
- **Compression**: create 7z / ZIP / TAR archives with selectable compression
  levels and optional password (AES-256 for ZIP, encrypted headers for 7z),
  with a New Archive options sheet and live progress.

## [0.2.0] — 2026-07-08

### Added
- **Extraction**: extract the whole archive or a selection into a chosen folder,
  with live progress, throughput, ETA and cancellation.

## [0.1.0] — 2026-07-08

### Added
- Initial foundation: open and browse archives (sortable file list, status bar),
  driven by the bundled official `7zz` engine through `SevenZipKit`.
- App icon and ad-hoc build/sign/launch script.
