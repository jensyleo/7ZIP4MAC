# 7ZIP4MAC — Roadmap

A native macOS GUI for the official 7-Zip engine. Phases 1–3 are complete;
what follows is the agreed plan for the next phases.

## ✅ Phase 1 — Core (done)
Open & browse archives, extract (all / selection), create archives
(7z / ZIP / TAR, levels, password), with live progress / throughput / ETA and
cancellation. Backed by `SevenZipKit` (bridge over the bundled `7zz`).

## ✅ Phase 2 — macOS integration (done)
Drag-out to Finder (file promise), Quick Look preview, Preferences window,
document types. (The Finder Sync extension + custom URL scheme built in this
phase were later **removed entirely** — macOS requires a paid Apple
Developer ID signature for `pluginkit` to ever accept a Finder Sync
extension, which this ad-hoc-signed build doesn't have, so it could never
actually work. See CHANGELOG.)

### Deferred, optional: Finder integration (needs a paid Apple Developer ID)
Right-click "Compress with 7ZIP4MAC" / a "7ZIP4MAC ▸ Compress…/Extract"
Finder submenu is **not planned work**, but remains **optional for whoever
has a paid Apple Developer ID account** (~$99/year): with a real Developer
ID Application certificate (and ideally the hardened runtime + notarization)
to sign the Finder Sync extension, `pluginkit` would accept it and the
integration could be rebuilt — it's a proven, previously-implemented
feature, just blocked by the signing requirement, not by anything
architectural. Not to be attempted again without a Developer ID in hand.

## ✅ Phase 3 — Power features (done)
Benchmark window, compression profiles (built-in + custom) with volume
splitting, recent archives, and an unlock prompt for encrypted archives.
(Originally also stored passwords in the Keychain — that integration was
later **removed**; the password is now kept in memory only, for the current
session, never persisted. See CHANGELOG.)

---

## ✅ Phase 4 — Windows-style UX + file-type icons  (mostly done)
Bring the browsing experience closer to 7-Zip for Windows while staying within
Apple's Human Interface Guidelines.

- [x] **Hierarchical navigation inside the archive**: enter folders, breadcrumb
      bar, "up one level", double-click / Return to enter.
- [x] **Test archive** action (`7zz t`) with a pass/fail result.
- [x] **File-type icons**: branded document icon for owned archive types
      (Finder shows it), and real per-entry icons via `NSWorkspace` / UTType.
- [ ] **Archive editing toolbar** (deferred continuation): Add / Delete / Move /
      Rename inside the archive (`7zz a` / `d` / `rn`). Higher risk — modifies
      the archive in place; scoped as its own slice.
- [ ] back/forward history; remember column layout.

## ▶ Phase 5 — Distribution & parity with the other apps  (IN PROGRESS)
Make the app shippable and consistent with TCPV4MAC / HG4MAC.

- [x] **About window**: standard macOS About panel with 7-Zip LGPL credits
      (matches TCPV4MAC's convention).
- [x] **Help**: quick-reference NSAlert from the Help menu (matches TCPV4MAC).
- [ ] ~~GitHub publication prep~~ — **explicitly deferred for now** (owner's
      request, 2026-07-09). Do not touch README/CHANGELOG/ROADMAP/LICENSE
      publish workflow or the "Publicar GitHub" copy until asked.
- [x] Port useful pieces from **TCPV4MAC**:
    - `InspectorView` — done. Toggleable toolbar panel, closed by default
      (owner's request, 2026-07-09): path, attributes, size/ratio, modified,
      CRC, method, encrypted.
    - `RowColor` — done, as `EntryRowStatus`: folder/encrypted name tinting.
    - Context menu — done: Quick Look, Extract…, Copy Name, Copy Path.
      ~~Export listing to CSV/JSON~~ — **removed per owner's request**
      (2026-07-09): "doesn't make sense" for this app. Do not re-add without
      being asked.
    - `Uninstaller` — done (ported, adapted for this app's prefs/caches).
      **Not exercised for real** during verification (destructive — would
      remove the working /Applications install); reviewed by code inspection
      only. If it's ever tested for real, expect to have to rebuild afterwards.
    - `SingleInstance` — done and verified (`open -n` while running does not
      spawn a second process; the existing instance is activated instead).

## Phase 6 — Deep macOS integration  (the original PROJECT.md "Phase 4")
- [ ] **Auto-update** via Sparkle (appcast feed + EdDSA-signed updates).
- [ ] **AppleScript** scripting dictionary (`.sdef`) for compress / extract.
- [ ] **Shortcuts** actions via App Intents ("Compress files", "Extract archive").
- [ ] **Spotlight** importer (`.mdimporter`) to index archive contents so
      Spotlight can find files *inside* archives.

---

## Deferred, low priority: Password storage (Keychain / KeePass)
Keychain integration (saving archive passwords so the app doesn't ask again)
was implemented, then removed at the owner's request — passwords are now
kept in memory for the current session only, never persisted. KeePass
support (a pluggable `PasswordSource` with a KeePass backend, likely via
`keepassxc-cli`) was the planned next step for that layer and was dropped
along with it.

Left here as a **low-priority pending idea**, not active work — revisit only
if the owner asks for it again someday. If it comes back: explain the
approach in detail before implementing (per the owner's standing request for
this kind of feature).

---

See `BACKLOG.md` for smaller deferred polish items from Phases 1–3.
