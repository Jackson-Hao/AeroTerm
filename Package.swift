// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroTerm",
    defaultLocalization: "en-US",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AeroTerm", targets: ["AeroTerm"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.7"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "AeroTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel")
            ],
            path: "Sources/AeroTerm",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
