// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchDeck", targets: ["NotchDeck"])],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "NotchDeck", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchDeckTests", dependencies: ["NotchDeck", "NotchCore"])
    ]
)
