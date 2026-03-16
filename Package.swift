// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenScribe",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenScribe",
            targets: ["OpenScribe"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenScribe",
            exclude: ["Resources/AppInfo.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/OpenScribe/Resources/AppInfo.plist"
                ])
            ]
        ),
        .testTarget(
            name: "OpenScribeTests",
            dependencies: ["OpenScribe"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
