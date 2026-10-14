// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenBottle",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenBottleCore", targets: ["OpenBottleCore"]),
        .executable(name: "OpenBottle", targets: ["OpenBottle"])
    ],
    targets: [
        .target(name: "OpenBottleCore"),
        .executableTarget(name: "OpenBottle", dependencies: ["OpenBottleCore"]),
        .testTarget(name: "OpenBottleCoreTests", dependencies: ["OpenBottleCore"])
    ]
)
