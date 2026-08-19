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
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.10.0"),
        .package(url: "https://github.com/royalapplications/royalvnc.git", branch: "main"),
        .package(path: "Vendor/RDPKit")
    ],
    targets: [
        .executableTarget(
            name: "AeroTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "RoyalVNCKit", package: "royalvnc"),
                .product(name: "RDPKit", package: "RDPKit")
            ],
            path: "Sources/AeroTerm",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
