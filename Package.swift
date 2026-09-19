// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShortcutLens",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ShortcutLens",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ShortcutLensTests",
            dependencies: ["ShortcutLens"]
        )
    ]
)
