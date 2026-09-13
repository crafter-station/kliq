// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kliq",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Kliq",
            path: "Sources/Kliq",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
