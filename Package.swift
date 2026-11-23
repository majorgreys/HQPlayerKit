// swift-tools-version: 5.10
import PackageDescription

// Standalone HQPlayer control-protocol client (XML over TCP 4321).
let package = Package(
    name: "HQPlayerKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HQPlayerKit", targets: ["HQPlayerKit"]),
    ],
    targets: [
        .target(name: "HQPlayerKit"),
        .testTarget(
            name: "HQPlayerKitTests",
            dependencies: ["HQPlayerKit"]
        ),
    ]
)
