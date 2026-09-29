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
    dependencies: [
        // Parakeet speech-to-text on Core ML. Traits off: no NeMo text-normalization binary.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: [])
    ],
    targets: [
        .executableTarget(
            name: "OpenScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
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
