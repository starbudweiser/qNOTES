// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "qNOTES",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "qNOTESCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "qNOTES", dependencies: ["qNOTESCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "qNOTESTests", dependencies: ["qNOTESCore"]),
    ]
)
