// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YomanCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yoman", targets: ["YomanApp"]),
        .executable(name: "yoman-bridge", targets: ["YomanBridge"]),
    ],
    targets: [
        .target(name: "YomanCore"),
        .executableTarget(
            name: "YomanApp", dependencies: ["YomanCore"],
            // AppKit/Carbon callbacks are all main-thread; Swift 5 mode keeps that glue simple.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "YomanBridge", dependencies: ["YomanCore"]),
        .testTarget(name: "YomanCoreTests", dependencies: ["YomanCore"]),
    ]
)
