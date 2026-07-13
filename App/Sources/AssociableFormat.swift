import Foundation
import UniformTypeIdentifiers

/// A file format the user can choose to associate with 7ZIP4MAC (i.e. make
/// it the default app for double-clicking that extension in Finder), mirroring
/// 7-Zip for Windows' "System" options tab.
///
/// Covers every format the app can open, per the owner's request — including
/// 7z and ISO/DMG/PKG (macOS has strong built-in defaults for mounting/
/// installing the latter three, but the choice to override is the user's,
/// and macOS still shows its per-format confirmation dialog).
public struct AssociableFormat: Identifiable, Hashable, Sendable {
    public enum Tier: String, CaseIterable, Sendable {
        case common = "Common Archives"
        case lessCommon = "Less Common Archives"
        case diskImage = "Disk & Filesystem Images"
    }

    public let key: String
    public let displayName: String
    public let utTypeIdentifier: String
    public let tier: Tier

    public var id: String { key }

    public var utType: UTType? { UTType(utTypeIdentifier) }

    private static let ownPrefix = "com.jensyleo.sevenzip4mac"

    /// Every format the user can toggle association for, in display order.
    public static let all: [AssociableFormat] = [
        // MARK: Common (blue)
        .init(key: "7z", displayName: "7-Zip", utTypeIdentifier: "org.7-zip.7-zip-archive", tier: .common),
        .init(key: "zip", displayName: "ZIP", utTypeIdentifier: "public.zip-archive", tier: .common),
        .init(key: "rar", displayName: "RAR", utTypeIdentifier: "com.rarlab.rar-archive", tier: .common),
        .init(key: "tar", displayName: "TAR", utTypeIdentifier: "public.tar-archive", tier: .common),
        .init(key: "gz", displayName: "GZIP", utTypeIdentifier: "org.gnu.gnu-zip-archive", tier: .common),
        .init(key: "bz2", displayName: "BZIP2", utTypeIdentifier: "public.bzip2-archive", tier: .common),
        .init(key: "xz", displayName: "XZ", utTypeIdentifier: "org.tukaani.xz-archive", tier: .common),
        .init(key: "iso", displayName: "ISO", utTypeIdentifier: "public.iso-image", tier: .common),
        .init(key: "dmg", displayName: "DMG", utTypeIdentifier: "com.apple.disk-image-udif", tier: .common),
        .init(key: "cab", displayName: "CAB", utTypeIdentifier: "com.microsoft.cab", tier: .common),

        // MARK: Less common (orange)
        .init(key: "pkg", displayName: "PKG", utTypeIdentifier: "com.apple.installer-package-archive", tier: .lessCommon),
        .init(key: "cpio", displayName: "CPIO", utTypeIdentifier: "public.cpio-archive", tier: .lessCommon),
        .init(key: "z", displayName: "Z", utTypeIdentifier: "public.z-archive", tier: .lessCommon),
        .init(key: "xar", displayName: "XAR", utTypeIdentifier: "com.apple.xar-archive", tier: .lessCommon),
        .init(key: "xip", displayName: "XIP", utTypeIdentifier: "com.apple.xip-archive", tier: .lessCommon),
        .init(key: "arj", displayName: "ARJ", utTypeIdentifier: "\(ownPrefix).arj-archive", tier: .lessCommon),
        .init(key: "lzh", displayName: "LZH", utTypeIdentifier: "\(ownPrefix).lzh-archive", tier: .lessCommon),
        .init(key: "wim", displayName: "WIM", utTypeIdentifier: "\(ownPrefix).wim-archive", tier: .lessCommon),
        .init(key: "rpm", displayName: "RPM", utTypeIdentifier: "\(ownPrefix).rpm-archive", tier: .lessCommon),
        .init(key: "deb", displayName: "DEB", utTypeIdentifier: "\(ownPrefix).deb-archive", tier: .lessCommon),
        .init(key: "chm", displayName: "CHM", utTypeIdentifier: "\(ownPrefix).chm-archive", tier: .lessCommon),
        .init(key: "nsis", displayName: "NSIS", utTypeIdentifier: "\(ownPrefix).nsis-archive", tier: .lessCommon),
        .init(key: "lzma", displayName: "LZMA", utTypeIdentifier: "\(ownPrefix).lzma-archive", tier: .lessCommon),
        .init(key: "ar", displayName: "AR", utTypeIdentifier: "\(ownPrefix).ar-archive", tier: .lessCommon),

        // MARK: Disk & filesystem images (yellow)
        .init(key: "squashfs", displayName: "SquashFS", utTypeIdentifier: "\(ownPrefix).squashfs-image", tier: .diskImage),
        .init(key: "ext", displayName: "ext (2/3/4)", utTypeIdentifier: "\(ownPrefix).ext-image", tier: .diskImage),
        .init(key: "fat", displayName: "FAT", utTypeIdentifier: "\(ownPrefix).fat-image", tier: .diskImage),
        .init(key: "ntfs", displayName: "NTFS", utTypeIdentifier: "\(ownPrefix).ntfs-image", tier: .diskImage),
        .init(key: "hfs", displayName: "HFS+", utTypeIdentifier: "\(ownPrefix).hfs-image", tier: .diskImage),
        .init(key: "apfs", displayName: "APFS", utTypeIdentifier: "\(ownPrefix).apfs-image", tier: .diskImage),
        .init(key: "vhd", displayName: "VHD", utTypeIdentifier: "\(ownPrefix).vhd-image", tier: .diskImage),
        .init(key: "vhdx", displayName: "VHDX", utTypeIdentifier: "\(ownPrefix).vhdx-image", tier: .diskImage),
        .init(key: "vmdk", displayName: "VMDK", utTypeIdentifier: "\(ownPrefix).vmdk-image", tier: .diskImage),
        .init(key: "qcow", displayName: "QCOW", utTypeIdentifier: "\(ownPrefix).qcow-image", tier: .diskImage),
        .init(key: "vdi", displayName: "VDI", utTypeIdentifier: "\(ownPrefix).vdi-image", tier: .diskImage),
        .init(key: "udf", displayName: "UDF", utTypeIdentifier: "\(ownPrefix).udf-image", tier: .diskImage),
    ]

    /// All keys, for the "associated by default" set.
    public static var allKeys: Set<String> { Set(all.map(\.key)) }
}
