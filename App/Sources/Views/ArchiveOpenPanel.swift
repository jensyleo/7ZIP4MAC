import AppKit
import UniformTypeIdentifiers

/// Presents a native open panel filtered to supported archive types.
///
/// Kept out of the SwiftUI views so they stay declarative; this is a thin
/// AppKit shim returning the user's chosen URL.
@MainActor
enum ArchiveOpenPanel {
    /// The archive content types the app declares support for — matching
    /// every format the bundled engine's own format table (`7zz i`) lists as
    /// a real archive or disk image (excluding raw executables, partition
    /// tables and office-document containers, which aren't "archives" a user
    /// browses and would be confusing to claim). Types without a stable
    /// system UTType are declared as our own exported types in Info.plist
    /// (`UTExportedTypeDeclarations`) so Finder still recognizes them.
    /// Anything else can still be opened manually — `allowsOtherFileTypes`
    /// is on below.
    static var supportedContentTypes: [UTType] {
        var types: [UTType] = [.zip, .gzip, .archive, .data]

        // Formats with a stable, well-known system UTType.
        let systemIdentifiers = [
            "org.7-zip.7-zip-archive", "com.rarlab.rar-archive", "public.tar-archive",
            "public.bzip2-archive", "org.gnu.gnu-zip-archive",
            "public.iso-image", "com.microsoft.cab", "public.cpio-archive",
            "org.tukaani.xz-archive", "com.apple.disk-image-udif",
            "public.z-archive", "com.apple.xar-archive",
            "com.apple.installer-package-archive", "com.apple.xip-archive",
        ]

        // Formats the engine supports but macOS has no system UTType for;
        // these match our own `UTExportedTypeDeclarations` in Info.plist.
        let ownIdentifierSuffixes = [
            "arj-archive", "lzh-archive", "wim-archive", "rpm-archive", "deb-archive",
            "chm-archive", "nsis-archive", "lzma-archive", "ar-archive",
            "squashfs-image", "ext-image", "fat-image", "ntfs-image", "hfs-image",
            "apfs-image", "vhd-image", "vhdx-image", "vmdk-image", "qcow-image",
            "vdi-image", "udf-image",
        ]

        for identifier in systemIdentifiers {
            if let type = UTType(identifier) { types.append(type) }
        }
        for suffix in ownIdentifierSuffixes {
            if let type = UTType("com.jensyleo.sevenzip4mac." + suffix) { types.append(type) }
        }
        return types
    }

    /// Shows the panel and returns the selected URL, or nil if cancelled.
    static func present() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedContentTypes
        panel.allowsOtherFileTypes = true
        panel.prompt = "Open"
        panel.message = "Choose an archive to open"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Presents a native panel for choosing a destination folder for extraction.
@MainActor
enum DestinationPanel {
    /// Shows the panel and returns the chosen folder, or nil if cancelled.
    static func present(suggestedName: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Extract"
        panel.message = suggestedName.map { "Choose where to extract “\($0)”" } ?? "Choose a destination folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Presents a panel for choosing files/folders to add to a new archive.
@MainActor
enum SourceSelectionPanel {
    static func present() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        panel.message = "Choose files and folders to compress"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Presents a save panel for the archive to create.
@MainActor
enum SavePanel {
    static func present(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.prompt = "Create"
        panel.message = "Save the new archive"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Prompts for a new internal path — used by "Move…"/"Copy…" in the file
/// list's context menu, which need a path *within* the archive rather than a
/// filesystem location (so a save/open panel doesn't apply).
@MainActor
enum PathPromptPanel {
    static func present(title: String, message: String, currentValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = currentValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
