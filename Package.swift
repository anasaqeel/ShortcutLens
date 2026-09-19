// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CheatSheet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CheatSheet",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CheatSheetTests",
            dependencies: ["CheatSheet"]
        )
    ]
)
