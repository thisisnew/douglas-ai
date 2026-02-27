// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DOUGLAS",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DOUGLASLib",
            path: "DOUGLAS",
            exclude: [
                "Resources/DOUGLAS.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/douglas_profile.png")
            ]
        ),
        .executableTarget(
            name: "DOUGLAS",
            dependencies: ["DOUGLASLib"],
            path: "DOUGLASApp"
        ),
        .testTarget(
            name: "DOUGLASTests",
            dependencies: ["DOUGLASLib"],
            path: "Tests"
        )
    ]
)
