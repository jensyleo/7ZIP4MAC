// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SevenZipKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SevenZipKit", targets: ["SevenZipKit"]),
        .executable(name: "sevenzip-cli", targets: ["sevenzip-cli"])
    ],
    targets: [
        .target(
            name: "SevenZipKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "sevenzip-cli",
            dependencies: ["SevenZipKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SevenZipKitTests",
            dependencies: ["SevenZipKit"],
            resources: [
                .process("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
