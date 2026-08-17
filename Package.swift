// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CursorRestorer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CursorRestorer",
            targets: ["CursorRestorer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CursorRestorer",
            path: "Sources/CursorAnchor"
        )
    ]
)
