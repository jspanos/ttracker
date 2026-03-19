// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ttracker",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ttracker",
            path: "Sources/ttracker",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("WebKit"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
