// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hearsay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hearsay", targets: ["Hearsay"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Hearsay",
            dependencies: [
                "ObjCExceptionCatcher",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/Hearsay"
        ),
        .target(name: "ObjCExceptionCatcher", path: "Sources/ObjCExceptionCatcher"),
        .testTarget(
            name: "HearsayTests",
            dependencies: ["Hearsay", "ObjCExceptionCatcher"],
            path: "Tests/HearsayTests"
        ),
    ]
)
