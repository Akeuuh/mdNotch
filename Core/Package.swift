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
    ]
)
