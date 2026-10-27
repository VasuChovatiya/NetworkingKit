// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkingKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "NetworkingKit", targets: ["NetworkingKit"]),
        .library(name: "NetworkingKitTesting", targets: ["NetworkingKitTesting"]),
    ],
    targets: [
        .target(name: "NetworkingKit"),
        .target(
            name: "NetworkingKitTesting",
            dependencies: ["NetworkingKit"]
        ),
        .testTarget(
            name: "NetworkingKitTests",
            dependencies: ["NetworkingKit", "NetworkingKitTesting"]
        ),
    ]
)
