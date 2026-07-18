// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatDidISay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatDidISay", targets: ["WhatDidISay"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "WhatDidISay",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift")
            ],
            path: "Sources/WhatDidISay"
        ),
        .testTarget(
            name: "WhatDidISayTests",
            dependencies: ["WhatDidISay"],
            path: "Tests/WhatDidISayTests"
        )
    ]
)
