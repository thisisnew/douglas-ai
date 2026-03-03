// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DOUGLAS",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "DOUGLAS",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
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
