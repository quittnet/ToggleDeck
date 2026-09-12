// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToggleDeck",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "ToggleDeck",
            path: "Sources/ToggleDeck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ToggleDeckTests", dependencies: ["ToggleDeck"]),
    ]
)
