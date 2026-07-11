// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ShadowCoach",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ShadowCoach", targets: ["ShadowCoach"])
    ],
    targets: [
        .executableTarget(
            name: "ShadowCoach",
            path: "Sources/ShadowCoach"
        ),
        .testTarget(
            name: "ShadowCoachSmokeTests",
            path: "Tests/ShadowCoachSmokeTests"
        )
    ]
)
