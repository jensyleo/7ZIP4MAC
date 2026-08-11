import SwiftUI
import AppKit

/// Resolves the `NSWindow` actually hosting this SwiftUI view. Used by
/// ``ArchiveWindowRoot`` to register itself in ``OpenArchiveWindowRegistry``
/// without depending on `NSApp.keyWindow` (unreliable when the open request
/// arrives while some other window is frontmost).
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
