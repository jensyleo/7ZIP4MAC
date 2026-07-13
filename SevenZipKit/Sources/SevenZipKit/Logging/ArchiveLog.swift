import Foundation
import OSLog

/// Central logger for engine operations.
///
/// Every important operation (listing started/finished/failed) is logged.
/// Passwords are never included in any log message.
public enum ArchiveLog {
    public static let engine = Logger(subsystem: "com.jensyleo.sevenzip4mac", category: "engine")
    public static let service = Logger(subsystem: "com.jensyleo.sevenzip4mac", category: "service")
    public static let ui = Logger(subsystem: "com.jensyleo.sevenzip4mac", category: "ui")
}
