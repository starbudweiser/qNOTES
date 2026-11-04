// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "qNOTES",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "qNOTESCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "qNOTES", dependencies: ["qNOTESCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "qNOTESWidget", dependencies: ["qNOTESCore"], swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
                                           .linkedFramework("WidgetKit"), .linkedFramework("SwiftUI")]),
        .testTarget(name: "qNOTESTests", dependencies: ["qNOTESCore"]),
    ]
)
