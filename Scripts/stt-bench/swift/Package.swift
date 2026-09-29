// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "STTBench",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: [])
    ],
    targets: [
        .executableTarget(
            name: "STTBench",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
