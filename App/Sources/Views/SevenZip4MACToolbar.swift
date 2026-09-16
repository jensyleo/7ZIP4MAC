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
/// running). Bridging to a real, hand-built `NSToolbar` per window sidesteps
/// this entirely: each window's `NSToolbar` is its own AppKit object, never
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
    private static let symbolCache = NSCache<NSString, NSImage>()

    private func loadSavedOrder() -> [String]? {
        UserDefaults.standard.array(forKey: Self.orderDefaultsKey) as? [String]
    }

    /// Persists this toolbar's current item order — called only in response
    /// to `NSToolbar`'s own add/remove notifications (wired up in
    /// `install(on:actions:)`), which fire exclusively when the user actually
    /// drags/removes an item via the customization sheet or its shortcuts.
    /// `setActions` refreshing dynamic item state (title/enabled/image) on
    /// every render never touches this — with more than one window open,
    /// saving unconditionally on every render would let a window nobody has
    /// touched since launch stomp another window's just-completed manual
    /// reorder with its own untouched, merely-stale copy of the order.
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

    /// Fires only when the user actually drags a new item onto the toolbar
    /// (from the customization sheet) or reorders existing ones — never from
    /// `setActions`'s per-render property refresh. See `saveCurrentOrder`'s
    /// doc comment for why that distinction matters with multiple windows.
    func toolbarWillAddItem(_ notification: Notification) {
        guard let toolbar else { return }
        saveCurrentOrder(toolbar)
    }

    func toolbarDidRemoveItem(_ notification: Notification) {
        guard let toolbar else { return }
        saveCurrentOrder(toolbar)
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
            // Always true — see `toolbar(_:itemForItemIdentifier:...)`'s own
            // doc comment on why `item.isEnabled` never reflects `spec.isEnabled`.
            item.isEnabled = true
            if let menuItem = item as? NSMenuToolbarItem, case let .menu(build) = spec.kind {
                menuItem.menu = build()
            } else if let systemImage = spec.systemImage {
                item.image = symbolImage(systemImage, isDestructive: spec.isDestructive, isEnabled: spec.isEnabled)
            }
        }
    }

    /// System symbol images never change per-window, so they're cached by
    /// (name, isDestructive, isEnabled) instead of rebuilt on every
    /// `setActions` call — which otherwise fires on every render (a
    /// selection change, a folder navigation, an extraction progress tick),
    /// re-allocating an `NSImage`/`SymbolConfiguration` pair for all ~14
    /// toolbar items each time even though at most one or two actually
    /// changed.
    ///
    /// `isEnabled` bakes the disabled look directly into the returned
    /// bitmap (see `dimmed(_:)`) instead of relying on `NSToolbarItem`'s own
    /// dynamic dimming — confirmed on video (2026-09-16, jensyleo's own
    /// screen recording) that a disabled icon's dimming briefly drops out
    /// whenever the mouse comes near it or any other toolbar item, showing
    /// the full-brightness "enabled" artwork for a frame or two before
    /// reverting; a fixed `SymbolConfiguration` on the image made this
    /// *worse* (an earlier, reverted attempt — see git history), pointing at
    /// AppKit's own disabled-state rendering rather than anything about the
    /// image's configuration. ROMForge's own hand-built toolbar, same
    /// disabled-icon pattern, shows nothing like it — but every one of its
    /// disabled items is inside an `NSMenuToolbarItem` dropdown, never a
    /// plain disabled `NSToolbarItem` like these; baking the dimming into
    /// the bitmap sidesteps that dynamic path entirely rather than
    /// depending on which item style avoids the bug.
    /// A visibly larger toolbar glyph than AppKit's own default point size
    /// — jensyleo's own request (2026-09-16): "sigo viendo los iconos muy
    /// chicos". Safe to bake into the image now (unlike the earlier,
    /// reverted attempt at a fixed configuration — see git history and
    /// this method's own doc comment): that attempt fought
    /// `NSToolbarItem`'s *dynamic* disabled-state dimming, which no longer
    /// runs at all now that `item.isEnabled` is always `true`. Nothing here
    /// depends on that dynamic path anymore, so a fixed size doesn't
    /// resurrect the flicker it caused before.
    private static let symbolSize = NSImage.SymbolConfiguration(pointSize: 19, weight: .medium)

    private func symbolImage(_ name: String, isDestructive: Bool, isEnabled: Bool) -> NSImage? {
        let key = "\(name)|\(isDestructive)|\(isEnabled)" as NSString
        if let cached = Self.symbolCache.object(forKey: key) { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var config = Self.symbolSize
        if isDestructive {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        var result = image.withSymbolConfiguration(config) ?? image
        if !isEnabled {
            result = Self.dimmed(result)
        }
        Self.symbolCache.setObject(result, forKey: key)
        return result
    }

    /// Renders `image` at reduced opacity into a fresh bitmap — a disabled
    /// toolbar icon's look baked in up front, not left to `NSToolbarItem`'s
    /// own (unreliable, see `symbolImage`'s own doc comment) disabled-state
    /// dimming. `0.35` is a plain visual match for the system's own
    /// disabled-icon opacity, not a value with any other significance.
    private static func dimmed(_ image: NSImage) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero, operation: .sourceOver, fraction: 0.35
        )
        result.unlockFocus()
        result.isTemplate = image.isTemplate
        return result
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
                item.image = symbolImage(systemImage, isDestructive: spec.isDestructive, isEnabled: spec.isEnabled)
            }
            item.showsIndicator = true
            return item
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = spec.title
        item.paletteLabel = spec.title
        item.toolTip = spec.help
        // Deliberately always true — never `spec.isEnabled`. `NSToolbarItem`
        // computes its own dimmed appearance dynamically from `isEnabled`,
        // and that computation intermittently drops out on every redraw
        // (confirmed on video, 2026-09-16: a disabled icon briefly flashes
        // full-brightness "enabled" artwork, several times a second, with
        // the mouse completely motionless — this app re-renders its
        // SwiftUI tree at a constant ~60fps regardless of any user
        // interaction, confirmed present as far back as v1.7.4, so every
        // one of those frames is a chance for the dimming computation to
        // glitch). Leaving `isEnabled` always true means AppKit never
        // computes a dimmed state at all — the disabled *look* comes
        // entirely from `symbolImage`'s own pre-dimmed bitmap instead,
        // which is static and can't flicker. `performAction` below enforces
        // the real enabled/disabled behavior (whether the click actually
        // does anything), so nothing here regresses actual functionality.
        item.isEnabled = true
        item.target = self
        item.action = #selector(performAction(_:))
        if let systemImage = spec.systemImage {
            item.image = symbolImage(systemImage, isDestructive: spec.isDestructive, isEnabled: spec.isEnabled)
        }
        return item
    }

    @objc private func performAction(_ sender: NSToolbarItem) {
        guard let spec = actionsByID[sender.itemIdentifier.rawValue], spec.isEnabled else { return }
        guard case let .button(action) = spec.kind else { return }
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
        context.coordinator.pendingActions = actions
        // Exactly one of these ever actually applies per burst of renders:
        // if a deferred apply from an earlier call is already scheduled,
        // this call only refreshes `pendingActions` (picked up when that
        // scheduled apply runs) and returns — applying immediately here
        // *as well*, on a still-Bool-guarded second path, was a real race
        // that briefly ran the toolbar with a stale `actions` snapshot
        // (every item shown enabled, mid-launch, for exactly one frame)
        // right before the already-scheduled apply corrected it a moment
        // later — confirmed on video, 2026-09-16.
        guard !context.coordinator.isScheduled else { return }
        let coordinator = context.coordinator
        func apply(on view: NSView) {
            coordinator.isScheduled = false
            guard let window = view.window, let actions = coordinator.pendingActions else { return }
            controller.install(on: window, actions: actions)
            controller.setActions(actions)
        }
        // `nsView.window` is nil until AppKit has actually attached this
        // view into a window's view hierarchy — true on the very first
        // `updateNSView` call, but SwiftUI's initial layout pass re-invokes
        // this several times before the window is ever shown on screen, so
        // the window is very often already available by one of those later
        // calls. Applying immediately whenever that's already true (rather
        // than always deferring one run-loop turn via
        // `DispatchQueue.main.async`) closes the window where the toolbar
        // was still empty right as the window first became visible.
        if nsView.window != nil {
            apply(on: nsView)
        } else {
            coordinator.isScheduled = true
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else { coordinator.isScheduled = false; return }
                apply(on: nsView)
            }
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
