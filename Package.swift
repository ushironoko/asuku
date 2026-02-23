// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "asuku",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            exact: "1.18.9"
        ),
    ],
    targets: [
        // Shared library (IPC protocol, socket, webhook parser)
        .target(
            name: "AsukuShared",
            path: "Sources/AsukuShared"
        ),

        // App core library (pure data types, testable without AppKit/SwiftUI)
        .target(
            name: "AsukuAppCore",
            dependencies: ["AsukuShared"],
            path: "Sources/AsukuAppCore"
        ),

        // Menu bar app
        .executableTarget(
            name: "AsukuApp",
            dependencies: ["AsukuShared", "AsukuAppCore"],
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
            dependencies: [
                "AsukuShared",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/AsukuSharedTests"
        ),
        .testTarget(
            name: "AsukuAppCoreTests",
            dependencies: [
                "AsukuAppCore",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/AsukuAppCoreTests"
        ),
        .testTarget(
            name: "AsukuHookTests",
            dependencies: [
                "AsukuShared",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/AsukuHookTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["AsukuShared"],
            path: "Tests/IntegrationTests"
        ),
    ]
)
