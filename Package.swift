// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DOUGLAS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DOUGLAS",
            path: "Sources",
            exclude: [
                "Resources/DOUGLAS.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/douglas_profile.png")
            ]
        ),
        .testTarget(
            name: "DOUGLASTests",
            dependencies: ["DOUGLAS"],
            path: "Tests"
        )
    ]
)
