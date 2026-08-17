// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroTerm",
    defaultLocalization: "en-US",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AeroTerm", targets: ["AeroTerm"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.7")
    ],
    targets: [
        .executableTarget(
            name: "AeroTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/AeroTerm",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
