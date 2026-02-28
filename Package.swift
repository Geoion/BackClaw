// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackClaw",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "BackClaw",
            targets: ["BackClaw"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BackClaw",
            path: ".",
            exclude: [
                "Tests",
                "PRD.md",
                "LICENSE",
                ".gitignore"
            ],
            sources: [
                "App",
                "Domain",
                "Services",
                "Storage",
                "Features"
            ]
        ),
        .testTarget(
            name: "BackClawTests",
            dependencies: ["BackClaw"],
            path: "Tests"
        )
    ]
)
