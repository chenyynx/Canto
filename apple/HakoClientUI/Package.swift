// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HakoClientUI",
    platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "HakoClientUI", targets: ["HakoClientUI"])],
    targets: [
        .target(
            name: "HakoClientUI",
            path: "Sources/HakoClientUI",
            sources: [".", "../../../HakoAgentKit/Sources/HakoAgentKit", "../../../HakoClientKit/Sources/HakoClientKit"],
            swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS, .macOS], configuration: .release))]
        )
    ]
)
