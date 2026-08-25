import AppKit
import SwiftUI

/// A plain `NSMenuItem` that carries its own action as a closure instead of
/// a target/selector pair, so a `ToolbarAction.Kind.menu` builder can attach
/// per-window closures (e.g. "Uninstall…") without a matching `@objc` method.
final class ClosureMenuItem: NSMenuItem {
    private var handler: () -> Void = {}

    convenience init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
        self.handler = handler
    }

    @objc private func fire() { handler() }
}

/// One toolbar item declared by `ContentView` and kept in sync with a real,
/// hand-built `NSToolbar` by `SevenZip4MACToolbarController`. SwiftUI's own
/// `.toolbar(id:) { ToolbarItem(id:) { ... } }` — tried first — turns on
/// `allowsUserCustomization`, but on macOS 26.6.2 it crashes the moment a
/// second window opens: `NSToolbar._insertNewItemWithItemIdentifier` fails
/// restoring `CustomizableToolbarContent`'s saved layout when multiple
/// windows share the same `toolbar(id:)` (reproduced deterministically —
/// launch the app, then `open` a second file from the Finder/CLI while it's
/// running). Bridging to a real, hand-built `NSToolbar` per window — same
/// approach as TCPV4MAC's `TCPV4MACToolbarController` — sidesteps this
/// entirely: each window's `NSToolbar` is its own AppKit object, never
/// reconciled by SwiftUI's cross-window `.toolbar(id:)` machinery.
struct ToolbarAction: Identifiable {
    enum Kind {
        case button(() -> Void)
        /// Rebuilt fresh every time the menu is about to open, so its
        /// contents always reflect the current model (e.g. "Uninstall…").
        case menu(() -> NSMenu)
    }
    let id: String
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    var help: String = ""
    var kind: Kind
}

/// Owns one window's real `NSToolbar` and keeps it in sync with the
/// declarative `[ToolbarAction]` list `ContentView` recomputes on every
/// render. A single "main" region is enough for this app.
@MainActor
final class SevenZip4MACToolbarController: NSObject, NSToolbarDelegate {
    static let toolbarIdentifier = "SevenZip4MAC.mainToolbar.v1"
    private static let orderDefaultsKey = "SevenZip4MAC.toolbarOrder.v1"

    private var actionsByID: [String: ToolbarAction] = [:]
    private var orderedIDs: [String] = []
    private weak var toolbar: NSToolbar?

    private func loadSavedOrder() -> [String]? {
        UserDefaults.standard.array(forKey: Self.orderDefaultsKey) as? [String]
    }

    private func saveCurrentOrder(_ toolbar: NSToolbar) {
        let ids = toolbar.items.map(\.itemIdentifier.rawValue).filter { actionsByID[$0] != nil }
        UserDefaults.standard.set(ids, forKey: Self.orderDefaultsKey)
    }

    /// The saved order, with any ids it doesn't mention (new actions added
    /// since the user last reordered) appended at the end in their normal
    /// declared order, and any ids it mentions that no longer exist dropped.
    private func mergedOrder(current: [String], saved: [String]?) -> [String] {
        guard let saved else { return current }
        let currentSet = Set(current)
        let kept = saved.filter { currentSet.contains($0) }
        let newOnes = current.filter { !saved.contains($0) }
        return kept + newOnes
    }

    /// Installs this window's own `NSToolbar` if it doesn't already have
    /// one. Each window gets an independent `NSToolbar` instance (same
    /// identifier is fine — unlike SwiftUI's `.toolbar(id:)`, there's no
    /// shared declarative state for AppKit to reconcile across windows).
    func install(on window: NSWindow, actions: [ToolbarAction]) {
        if let existing = window.toolbar, existing.delegate === self {
            toolbar = existing
            return
        }
        orderedIDs = mergedOrder(current: actions.map(\.id), saved: loadSavedOrder())
        for action in actions { actionsByID[action.id] = action }

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        self.toolbar = toolbar
    }

    /// Declares (or replaces) the full current action list. Existing items
    /// already on the real toolbar only ever have their dynamic state
    /// (enabled/help/title/image) refreshed in place — order and visibility
    /// are the user's own to manage once installed; this method must NEVER
    /// remove+reinsert an item that's simply unchanged, or a manual reorder
    /// would be undone on the next refresh (every selection/state change).
    func setActions(_ newActions: [ToolbarAction]) {
        let previousIDs = Set(orderedIDs)
        let newIDs = newActions.map(\.id)
        orderedIDs = newIDs
        for action in newActions { actionsByID[action.id] = action }

        guard let toolbar else { return }
        reconcile(previousIDs: previousIDs, newIDs: newIDs, toolbar: toolbar)
        for item in toolbar.items {
            guard let spec = actionsByID[item.itemIdentifier.rawValue] else { continue }
            item.toolTip = spec.help
            item.label = spec.title
            item.isEnabled = spec.isEnabled
            if let menuItem = item as? NSMenuToolbarItem, case let .menu(build) = spec.kind {
                menuItem.menu = build()
            } else if let systemImage = spec.systemImage {
                item.image = symbolImage(systemImage, isDestructive: spec.isDestructive)
            }
        }
        saveCurrentOrder(toolbar)
    }

    private func symbolImage(_ name: String, isDestructive: Bool) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        guard isDestructive else { return image }
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        return image.withSymbolConfiguration(config)
    }

    /// Only sets, never `Set<String>` iteration order, decide the actual
    /// insertion sequence below — an unordered `Set` iteration here would
    /// scramble the on-screen order randomly on every launch. And the whole
    /// method is a no-op whenever the id *set* is unchanged (guarded above
    /// `setActions`'s per-item loop) — the real protection against undoing
    /// a user's drag reorder.
    private func reconcile(previousIDs: Set<String>, newIDs: [String], toolbar: NSToolbar) {
        let newIDSet = Set(newIDs)
        guard previousIDs != newIDSet else { return }
        for id in previousIDs.subtracting(newIDSet) {
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == id }) {
                toolbar.removeItem(at: index)
            }
        }
        for id in newIDs where !previousIDs.contains(id) {
            guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == id }) else { continue }
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: id), at: toolbar.items.count)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        orderedIDs.map { NSToolbarItem.Identifier(rawValue: $0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec = actionsByID[itemIdentifier.rawValue] else { return nil }

        if case let .menu(build) = spec.kind {
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = spec.title
            item.paletteLabel = spec.title
            item.toolTip = spec.help
            item.menu = build()
            if let systemImage = spec.systemImage {
                item.image = symbolImage(systemImage, isDestructive: spec.isDestructive)
            }
            item.showsIndicator = true
            return item
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = spec.title
        item.paletteLabel = spec.title
        item.toolTip = spec.help
        item.isEnabled = spec.isEnabled
        item.target = self
        item.action = #selector(performAction(_:))
        if let systemImage = spec.systemImage {
            item.image = symbolImage(systemImage, isDestructive: spec.isDestructive)
        }
        return item
    }

    @objc private func performAction(_ sender: NSToolbarItem) {
        guard case let .button(action) = actionsByID[sender.itemIdentifier.rawValue]?.kind else { return }
        action()
    }
}

/// Installs/updates `SevenZip4MACToolbarController`'s real `NSToolbar` on
/// this view's own window — an invisible, zero-size bridge, since SwiftUI
/// has no API to reach the containing `NSWindow` directly from a nested
/// view's body. Meant to be attached via `.background(...)` so it doesn't
/// affect layout.
struct ToolbarHost: NSViewRepresentable {
    let actions: [ToolbarAction]
    let controller: SevenZip4MACToolbarController

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // `nsView.window` is nil until AppKit has actually attached this
        // view into a window's view hierarchy, which hasn't necessarily
        // happened yet on the very first `updateNSView` call — deferred to
        // the next run-loop turn, and bursts of renders are coalesced into
        // a single pending apply.
        context.coordinator.pendingActions = actions
        guard !context.coordinator.isScheduled else { return }
        context.coordinator.isScheduled = true
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak nsView] in
            coordinator.isScheduled = false
            guard let nsView, let window = nsView.window, let actions = coordinator.pendingActions else { return }
            controller.install(on: window, actions: actions)
            controller.setActions(actions)
        }
    }

    @MainActor
    final class Coordinator {
        var pendingActions: [ToolbarAction]?
        var isScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
