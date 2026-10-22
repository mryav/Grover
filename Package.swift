// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Grover",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Grover",
            path: "Sources/Grover",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
