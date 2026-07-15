import AppKit

/// Full self-uninstall: removes the app's traces (preferences, saved state,
/// caches) and moves the bundle to the Trash. The main app is not
/// sandboxed, so this can clean everything it leaves behind.
@MainActor
enum Uninstaller {

    static func confirmAndUninstall(settings: AppSettings) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall 7ZIP4MAC?"
        alert.informativeText = """
        This will move 7ZIP4MAC to the Trash and remove everything it leaves on \
        this Mac: its preferences, saved state and caches. This cannot be undone.
        """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await perform(settings: settings) }
    }

    private static func perform(settings: AppSettings) async {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jensyleo.sevenzip4mac"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default

        // 0. Hand every format this app associated itself with back to
        //    whatever opened it before — the default-handler assignment is
        //    keyed by bundle identifier, not by whether the app still exists
        //    on disk, so without this it dangles on a deleted app forever
        //    (confirmed: `lsregister -u` in step 3 does NOT clear it).
        await FileAssociationService.restoreOriginals(settings: settings)

        // 1. Reset Privacy & Security (TCC) grants, saved state and caches.
        runToCompletion("/usr/bin/tccutil", ["reset", "All", bundleID])
        for path in ["Library/Saved Application State/\(bundleID).savedState",
                     "Library/Caches/\(bundleID)",
                     "Library/HTTPStorages/\(bundleID)"] {
            try? fm.removeItem(at: home.appendingPathComponent(path))
        }

        // 2. Preferences: delete AFTER we quit. Doing it in-process fails because
        //    cfprefsd flushes the domain back to disk on termination, recreating
        //    the .plist. A detached shell waits for quit, then `defaults delete`
        //    clears the daemon's cache and removes the file for good.
        let prefsCleanup = """
        sleep 2
        /usr/bin/defaults delete \(bundleID) 2>/dev/null
        /bin/rm -f "$HOME/Library/Preferences/\(bundleID).plist"
        """
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", prefsCleanup]
        try? sh.run()   // detached — do not wait; it outlives us

        // 3. Unregister from LaunchServices *before* trashing, so file
        //    associations (the default app for .7z/.zip/etc.) actually fall
        //    back to the system default (Archive Utility) instead of silently
        //    picking up some other stray copy of this same bundle ID elsewhere
        //    on disk (e.g. a leftover dev build) — LaunchServices doesn't do
        //    this on its own just because the app moved to the Trash.
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        runToCompletion(lsregister, ["-u", Bundle.main.bundleURL.path])

        // 4. Move the app bundle to the Trash.
        try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)

        // 5. Quit (lets the detached cleanup finish the prefs removal).
        NSApp.terminate(nil)
    }

    private static func runToCompletion(_ launchPath: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
