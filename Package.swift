// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RescreenBroker",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "RescreenBroker",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/RescreenBroker",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
