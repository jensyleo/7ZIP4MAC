# Backlog — deferred polish (Phases 1 & 2)

Items intentionally postponed to keep momentum. Grouped by area; not in strict
priority order.

## File-type icons (per format) — ✅ DONE (2026-07-09)
Owner drew all 36 icons (`Icons/filetype_icon_<key>_1024.png`, color-coded:
blue = common archives, orange = less-common archives, yellow = disk/
filesystem images). Wired: generated one `.icns` per format into
`App/Resources/FileTypeIcons/`, restructured `Info.plist` so
`CFBundleDocumentTypes` has one entry per format (each with its own
`CFBundleTypeIconFile`), and added `UTTypeIconFile` to each of our custom
`UTExportedTypeDeclarations`. Verified for real: asked `NSWorkspace` for the
icon of an actual `.arj` and `.chm` file on disk and got back the owner's
own artwork, not a generic icon.

- ✅ `filetype_icon_ext_024.png` (stray typo'd duplicate) deleted by the owner
  (2026-07-09). Confirmed the surviving `filetype_icon_ext_1024.png` is
  byte-identical (same MD5) to the source already wired into `ext.icns` —
  nothing to rebuild, no action needed.

Leftover, unused files in `Icons/` (not an error, just noting for later) — one
generic spare per color tier, none mapped to a declared format since every
format already got its own specific icon:
- `filetype_icon_disk_1024.png` (yellow — disk images)
- `filetype_icon_generic_blue_1024.png` (blue — common archives)
- `filetype_icon_generic_orange_1024.png` (orange — less-common archives;
  owner's file had a typo'd name with a stray "ç" and no size suffix,
  renamed to match the established `_1024.png` convention, 2026-07-09)

Kept as spares in case a future generic fallback UTI is needed (e.g. for an
archive-like extension the app doesn't specifically recognize); currently
unused/unwired.

## File list / explorer
- [x] Hierarchical folder navigation — done in Phase 4 (breadcrumbs + enter/Up).
- [x] CLOSED (2026-07-09): column reordering isn't wanted — the earlier report
      was a misunderstanding on the owner's part, not a real ask. Leave the
      Table's column behavior as-is; no `NSTableView` replacement needed.
- [x] Fixed (2026-07-09, per real user testing): row selection/double-click
      were unreliable ("hay que hacer muchos intentos"). Root cause was a
      custom gesture recognizer (`.onTapGesture`/`.simultaneousGesture`)
      racing against `Table`'s own click handling. Replaced with an explicit
      `Button` per row that reads `NSEvent.clickCount` and `.modifierFlags`
      directly — single click selects, ⌘-click toggles, Shift-click selects a
      range, a second click activates (enter folder / Quick Look). Please
      retest: single-click select, double-click into a folder and into a
      file, ⌘-click to add/remove from selection, Shift-click for a range.
- [ ] Column sort (Name/Size headers) reported as not visibly reordering.
      Reviewed the sort/derive-visible-rows logic and found no hard bug, but
      one likely explanation: folders are forced before files (matching
      Finder), and synthesized folder entries report size 0 (the engine
      doesn't recursively total folder sizes), so sorting by Size won't
      visibly reorder a folder-only view. Please retest specifically: open a
      folder with several **files** of different sizes and click the "Size"
      header twice (ascending/descending) — if files still don't reorder,
      that's a real bug to come back to with more detail (which column,
      what was expected vs seen).
- [ ] Consider computing recursive folder sizes (sum of descendants) so
      folders sort/display meaningfully by size — nice-to-have, not required.

## Performance
- [ ] User reports the app feels "un poco lenta" (2026-07-09) but didn't
      specify which action. Reviewed for obvious hot-path issues and applied
      one concrete fix: `BundledEngine.resolve()` was re-validating the
      bundled binary's path on every single operation (open/extract/test/
      compress/benchmark/drag-out) — now cached after first resolution.
      No other clear bottleneck found by static review (listing parse and
      `recomputeVisible()` are both O(n) over the archive, which should be
      fast for reasonable archive sizes). Needs the user to pinpoint which
      specific action feels slow (opening a large archive? navigating
      folders? extracting? general click responsiveness?) to investigate
      further with real data instead of guessing.

## Extraction
- [ ] Overwrite policy in the UI (overwrite / skip / rename). The engine already
      supports it (`ExtractionRequest.OverwritePolicy`); currently always
      overwrite.
- [x] Password prompt when opening encrypted archives — done (unlock sheet,
      in-memory for the session only; no Keychain — that integration was
      removed).
- [x] Quick Look and drag-out reuse the session password for encrypted
      archives — done. Both used to hardcode `password: nil`, so neither
      ever worked on an encrypted archive's entries.

## Drag & drop
- [ ] Multi-item drag-out. SwiftUI `.onDrag` yields a single item; dragging a
      multi-selection out to Finder needs a different (AppKit) path.
- [ ] Drag files *into* the window to start a New Archive (compress by drop).

## Quick Look
- [ ] Preview a multi-selection (arrow through items) instead of just the first.
- [ ] Reuse the extracted temp file across repeated previews of the same entry.

## Finder extension
- [ ] Live end-to-end verification of the real right-click menu (requires
      enabling in System Settings and `killall Finder`).
- [ ] Developer ID signing so the extension loads without manual approval on
      other machines. Currently ad-hoc signed.
- [ ] Progress/badge feedback in Finder while an operation runs.

## Housekeeping
- [ ] Clean up drag-out / Quick Look temporary extraction directories
      (`7ZIP4MAC-Drag-*` in the temp dir) after use.
- [ ] Localization (UI strings are English; consider Spanish).
- [x] App icon replaced with the owner's `Icons/app_icon_1024.png` (2026-07-09),
      generated into all AppIcon.appiconset sizes and installed. Still open:
      owner may keep iterating on the artwork later ("no me termina de
      convencer" 100%) — revisit if a refined version shows up.
