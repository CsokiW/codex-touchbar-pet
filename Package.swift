// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "CodexTouchBarPet",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "CodexTBPet", targets: ["CodexBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexBar",
            path: "Sources"
        )
    ]
)
