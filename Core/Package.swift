// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MdNotchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MdNotchCore", targets: ["MdNotchCore"])
    ],
    targets: [
        .target(name: "MdNotchCore"),
        .testTarget(name: "MdNotchCoreTests", dependencies: ["MdNotchCore"]),
        // Slow suite against the real frozen binary; skipped unless
        // MDNOTCH_INTEGRATION=1 (see Tests/MdNotchIntegrationTests/README.md).
        .testTarget(
            name: "MdNotchIntegrationTests",
            dependencies: ["MdNotchCore"],
            resources: [.copy("Samples")]
        ),
    ]
)
