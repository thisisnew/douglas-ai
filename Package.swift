// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AgentManagerLib",
            path: "AgentManager",
            exclude: [
                "Resources/AgentManager.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/douglas_profile.png")
            ]
        ),
        .executableTarget(
            name: "AgentManager",
            dependencies: ["AgentManagerLib"],
            path: "AgentManagerApp"
        ),
        .testTarget(
            name: "AgentManagerTests",
            dependencies: ["AgentManagerLib"],
            path: "Tests"
        )
    ]
)
