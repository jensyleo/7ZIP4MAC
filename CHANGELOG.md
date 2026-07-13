# Changelog

All notable changes to 7ZIP4MAC are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-07-11

First public release.

### Changed
- **Bundle identifier changed from `energy.erco.sevenzip4mac` to
  `com.jensyleo.sevenzip4mac`** (matching the developer ID prefix used by
  the author's other apps), including all 21 custom document-type UTIs
  (e.g. `energy.erco.sevenzip4mac.arj-archive` →
  `com.jensyleo.sevenzip4mac.arj-archive`) and the unified logging subsystem
  string. System state tied to the old identifier was cleaned up: file-type
  handler assignments (zip/tar/rar/xip/gzip/xz/cpio/bzip2/7z) re-pointed to
  the new identifier, stale preferences/TCC grants reset, and old
  LaunchServices registration removed. (One leftover — a sandboxed
  `~/Library/Containers/energy.erco.sevenzip4mac.FinderExtension` folder from
  the already-removed Finder extension — couldn't be deleted from the
  terminal, which macOS blocks without Full Disk Access; safe to delete
  manually via Finder.)

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
  UTType now have their own exported type declaration (`energy.erco.
  sevenzip4mac.*`) so Finder still recognizes them. Excluded on purpose: raw
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
- **About** and **Help** menu items, matching the other apps' convention
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
