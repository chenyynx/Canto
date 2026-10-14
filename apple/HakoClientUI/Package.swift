// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HakoClientUI",
    platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "HakoClientUI", targets: ["HakoClientUI"])],
    dependencies: [
        .package(name: "HakoAgentKit", path: "../HakoAgentKit"),
        .package(name: "HakoClientKit", path: "../HakoClientKit"),
    ],
    targets: [
        .target(
            name: "HakoClientUI",
            dependencies: [
                .product(name: "HakoAgentKit", package: "HakoAgentKit"),
                .product(name: "HakoClientKit", package: "HakoClientKit"),
            ],
            swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS, .macOS], configuration: .release))]
        )
    ]
)
