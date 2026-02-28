// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmartTranscript",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "SmartTranscript",
            targets: ["SmartTranscript"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SmartTranscript",
            exclude: ["Resources/AppInfo.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SmartTranscript/Resources/AppInfo.plist"
                ])
            ]
        ),
        .testTarget(
            name: "SmartTranscriptTests",
            dependencies: ["SmartTranscript"]
        )
    ]
)
