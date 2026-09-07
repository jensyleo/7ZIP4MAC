import Foundation

/// One page of the Help window — a sidebar of topics rather than one long
/// scrolling page, so a question has a place to be looked up rather than
/// scrolled to. Structure and styling deliberately mirror `HelpTopic`/
/// `HelpView` from jensyleo's own ROMForge.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HelpSection: Identifiable, Hashable {
    let id = UUID()
    var heading: String?
    var paragraphs: [String] = []
    /// Term-and-explanation rows, for actions and settings enumerated one
    /// after another.
    var rows: [Row] = []

    struct Row: Identifiable, Hashable {
        let id = UUID()
        let term: String
        let detail: String
        /// A quiet tag beside the term — a default value, "Off by default".
        var note: String?
    }
}

enum HelpLibrary {
    static let topics: [HelpTopic] = [
        HelpTopic(id: "what-it-does", title: "What 7ZIP4MAC does", symbol: "sparkles", sections: [
            HelpSection(paragraphs: [
                "7ZIP4MAC is a native interface for the official 7-Zip engine, bundled unmodified inside the app. It lets you browse, extract, create, and edit archives in most formats — 7z, ZIP, TAR, GZ, BZ2, XZ, RAR, ISO, CAB, CPIO, ARJ, LZH, WIM, RPM, DEB, CHM, and more.",
                "This app performs no compression itself — all archive operations run through the official 7-Zip engine.",
            ]),
        ]),
        HelpTopic(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", symbol: "keyboard", sections: [
            HelpSection(paragraphs: [
                "Only shortcuts 7ZIP4MAC itself actually implements — not every inherited standard macOS one (⌘W, ⌘Q, ⌘M), which every app already has and doesn't need repeating here.",
            ]),
            HelpSection(heading: "Archive window", rows: [
                .init(term: "⌘O", detail: "Open an archive."),
                .init(term: "⌘N", detail: "Create a new archive."),
                .init(term: "⌘E", detail: "Extract all items."),
                .init(term: "⌘⇧B", detail: "Open the Benchmark window."),
                .init(term: "Space / ⌘Y", detail: "Toggle Quick Look preview of selected items."),
                .init(term: "Return", detail: "Enter the selected folder."),
                .init(term: "Escape", detail: "Exit to parent folder (or close archive if at root)."),
            ]),
        ]),
        HelpTopic(id: "browsing", title: "Opening and browsing archives", symbol: "folder.badge.questionmark", sections: [
            HelpSection(heading: "Opening", paragraphs: [
                "Open an archive with File ▸ Open (⌘O) or by dragging a file onto the 7ZIP4MAC window. The archive's contents appear in a file list with icons, sizes, dates, and compression details.",
            ]),
            HelpSection(heading: "Navigation", paragraphs: [
                "Double-click a folder to enter it. Click the back/forward navigation arrows at the top to move between folders you've already opened. Press Return to enter a folder, or Escape to go back to its parent.",
                "The breadcrumb at the top shows your current location — click any part of it to jump directly to that level.",
            ]),
            HelpSection(heading: "Selection and preview", rows: [
                .init(term: "Select items", detail: "Click to select one, ⌘-click to toggle others, Shift-click to select a range."),
                .init(term: "Quick Look", detail: "Press Space or ⌘Y to preview one or more selected items; press again to close."),
                .init(term: "Drag to extract", detail: "Drag any selected item to Finder to extract just that item there (folders are extracted with their full contents)."),
            ]),
            HelpSection(heading: "Right-click menu", rows: [
                .init(term: "Extract", detail: "Extract the selected item to a destination you choose."),
                .init(term: "Reveal in Finder", detail: "Jump to the actual extracted file on disk (if it's already been extracted)."),
            ]),
        ]),
        HelpTopic(id: "extraction", title: "Extracting archives", symbol: "arrow.down.doc", sections: [
            HelpSection(heading: "Extract All", paragraphs: [
                "Click Extract All (⌘E) to extract the entire archive. You'll be asked to choose a destination folder. 7ZIP4MAC uses your Settings ▸ General overwrite policy (Overwrite / Skip / Rename Extracted File) if any files already exist at the destination.",
            ]),
            HelpSection(heading: "Extract selection", paragraphs: [
                "Select one or more items first, then Extract All extracts only those items instead, preserving their folder structure inside your chosen destination.",
            ]),
            HelpSection(heading: "Drag to Finder", paragraphs: [
                "Select an item and drag it straight to Finder or the Desktop — 7ZIP4MAC extracts just that item there without ever asking where. Useful for quick access to single files; nothing is deleted from the archive.",
            ]),
            HelpSection(heading: "Overwrite policy", paragraphs: [
                "When an extracted filename already exists at the destination, 7ZIP4MAC applies your chosen policy from Settings ▸ General: Overwrite (replace the old file), Skip (keep the old file), or Rename Extracted File (add a number like \"file (2).txt\").",
            ]),
        ]),
        HelpTopic(id: "creating", title: "Creating archives", symbol: "arrow.up.doc", sections: [
            HelpSection(heading: "New Archive", paragraphs: [
                "Click File ▸ New Archive (⌘N) or Tools ▸ New Archive to start. You'll be asked to choose files or folders to add. 7ZIP4MAC then opens a window to choose format, compression level, optional password, and other settings.",
            ]),
            HelpSection(heading: "Format", paragraphs: [
                "7ZIP4MAC can create 7z, ZIP, or TAR archives. 7z offers the best compression; ZIP is universal; TAR is common on Unix/Linux systems (often compressed separately as .tar.gz or .tar.bz2).",
            ]),
            HelpSection(heading: "Compression level", paragraphs: [
                "From Store (no compression) to Ultra (slowest, smallest). Settings ▸ General lets you set a default level for new archives.",
            ]),
            HelpSection(heading: "Password", paragraphs: [
                "Optionally add a password to the archive. For 7z and ZIP, you can choose to encrypt the file list too (\"Encrypt Filenames\"), so the contents themselves are hidden from anyone without the password.",
            ]),
            HelpSection(heading: "Profiles", paragraphs: [
                "Save your preferred format/level/password combination as a profile in Settings ▸ Profiles, then reuse it in future archives — a quick way to apply the same settings without typing them every time.",
            ]),
        ]),
        HelpTopic(id: "editing", title: "Editing archives", symbol: "pencil.and.scribble", sections: [
            HelpSection(heading: "Add / Rename / Delete", paragraphs: [
                "Right-click any item to Add new files, Rename the item, Move it to a different folder inside the archive, Copy it to another archive, or Delete it. The archive is modified in place — no full re-compression needed, so edits are fast.",
            ]),
            HelpSection(heading: "Move between archives", paragraphs: [
                "Drag an item from one archive window to another to copy it. Both windows must be open in 7ZIP4MAC (Finder drag-and-drop isn't supported for this). The item is copied, not removed from the original.",
            ]),
            HelpSection(heading: "Limitations", paragraphs: [
                "Editing is not supported for archives that are themselves inside another archive — you'd need to extract the parent archive first.",
            ]),
        ]),
        HelpTopic(id: "passwords", title: "Encrypted archives", symbol: "lock.fill", sections: [
            HelpSection(paragraphs: [
                "When you open a password-protected archive, 7ZIP4MAC asks for the password. It's kept only in memory for that session and never written to disk or saved anywhere.",
            ]),
            HelpSection(heading: "Wrong password", paragraphs: [
                "If you enter the wrong password, extraction will fail partway through, or files will be corrupt. The prompt caps out at 3 attempts before resetting the window — start over and try again.",
            ]),
            HelpSection(heading: "Encrypted filenames", paragraphs: [
                "Some archives (7z or ZIP with encryption on) hide the filename list too — you won't see what's inside until you provide the password. 7ZIP4MAC still works normally after that.",
            ]),
        ]),
        HelpTopic(id: "test-verify", title: "Testing and verification", symbol: "checkmark.circle", sections: [
            HelpSection(heading: "Test Archive", paragraphs: [
                "Click Tools ▸ Test Archive to verify an archive's integrity without extracting it — checks for corruption or truncation. If anything is wrong, an error message tells you what's broken.",
            ]),
            HelpSection(heading: "Benchmark", paragraphs: [
                "Click Tools ▸ Benchmark (⌘⇧B) to measure how fast this Mac can compress data. Useful to tune your compression level choice for your own hardware.",
            ]),
        ]),
        HelpTopic(id: "toolbar", title: "Toolbar customization", symbol: "wrench.and.screwdriver", sections: [
            HelpSection(paragraphs: [
                "Right-click (or ⌘-drag) the toolbar to reorder items or show/hide them — your layout is remembered across launches.",
            ]),
        ]),
        HelpTopic(id: "settings", title: "Settings", symbol: "gearshape", sections: [
            HelpSection(heading: "General", paragraphs: [
                "Set your default archive format (7z / ZIP / TAR), default compression level (Store to Ultra), default password encryption, and the overwrite policy for extracted files (Overwrite / Skip / Rename).",
            ]),
            HelpSection(heading: "File Types", paragraphs: [
                "Make 7ZIP4MAC the default handler for any archive formats. Click \"Associate Recommended Files…\" to associate common formats all at once; macOS will confirm each one.",
            ]),
            HelpSection(heading: "Profiles", paragraphs: [
                "Save preset combinations of format, compression level, and password settings so you can reuse them in future archives without re-typing.",
            ]),
            HelpSection(heading: "Automation", paragraphs: [
                "Enable AppleScript and Shortcuts/Siri automation (both off by default) to let other apps and scripts control 7ZIP4MAC.",
            ]),
        ]),
    ]
}
