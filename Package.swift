// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "asuku",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        // Shared library
        .target(
            name: "AsukuShared",
            path: "Sources/AsukuShared"
        ),

        // Menu bar app
        .executableTarget(
            name: "AsukuApp",
            dependencies: ["AsukuShared"],
            path: "Sources/AsukuApp",
            exclude: ["Info.plist"]
        ),

        // CLI hook helper
        .executableTarget(
            name: "asuku-hook",
            dependencies: ["AsukuShared"],
            path: "Sources/AsukuHook"
        ),

        // Tests
        .testTarget(
            name: "AsukuSharedTests",
            dependencies: ["AsukuShared"],
            path: "Tests/AsukuSharedTests"
        ),
        .testTarget(
            name: "AsukuHookTests",
            dependencies: ["AsukuShared"],
            path: "Tests/AsukuHookTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["AsukuShared"],
            path: "Tests/IntegrationTests"
        ),
    ]
)
