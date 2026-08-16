// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BoltSnip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BoltSnip", targets: ["BoltSnip"])
    ],
    targets: [
        .executableTarget(
            name: "BoltSnip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
