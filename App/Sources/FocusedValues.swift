import SwiftUI

/// Exposes the frontmost window's per-document state to the App-level
/// Commands (File menu), which no longer own a single shared view model now
/// that each window has its own `ArchiveViewModel`/`CompressionViewModel`.
private struct FocusedArchiveViewModelKey: FocusedValueKey {
    typealias Value = ArchiveViewModel
}

private struct FocusedCompressionViewModelKey: FocusedValueKey {
    typealias Value = CompressionViewModel
}

extension FocusedValues {
    var archiveViewModel: ArchiveViewModel? {
        get { self[FocusedArchiveViewModelKey.self] }
        set { self[FocusedArchiveViewModelKey.self] = newValue }
    }

    var compressionViewModel: CompressionViewModel? {
        get { self[FocusedCompressionViewModelKey.self] }
        set { self[FocusedCompressionViewModelKey.self] = newValue }
    }
}
