// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MDNoteCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MDNoteCore", targets: ["MDNoteCore"]),
    ],
    targets: [
        .target(name: "MDNoteCore"),
        .testTarget(
            name: "MDNoteCoreTests",
            dependencies: ["MDNoteCore"]
        ),
    ]
)
