// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ClashMacClient", platforms: [.macOS(.v13)], products: [.library(name: "ClashMacClient", targets: ["ClashMacClient"])], dependencies: [.package(path: "../ClashClientKit"), .package(path: "../ClashClientUI")], targets: [.target(name: "ClashMacClient", dependencies: ["ClashClientKit", "ClashClientUI"], resources: [.process("Resources")])])
