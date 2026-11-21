// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Linky",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Linky",
            path: "Sources/Linky",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
