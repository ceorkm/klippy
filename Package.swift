// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Klippy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Klippy",
            targets: ["Klippy"]
        )
    ],
    dependencies: [
        // Add any external dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "Klippy",
            dependencies: [],
            path: "Sources",
            exclude: ["DataModel.xcdatamodeld"]
        ),
        .testTarget(
            name: "KlippyTests",
            dependencies: ["Klippy"],
            path: "Tests"
        )
    ]
)
