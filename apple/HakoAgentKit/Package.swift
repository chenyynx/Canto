// swift-tools-version: 6.0
import PackageDescription

// HakoAgentKit — Anchor 协议的 Swift 实现（纯逻辑，不依赖 iOS 运行环境）。
// 与 agent 端（TS, chenyynx/anchor）共享测试向量互验：
//   - vectors.json（信封/配对/路由，JSON Schema 契约）
//   - vectors-noise.json（Noise_XX 字节级黄金向量，gen-noise-vectors.ts 生成）
let package = Package(
    name: "HakoAgentKit",
    platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)],
    products: [
        .library(name: "HakoAgentKit", targets: ["HakoAgentKit"]),
    ],
    dependencies: [
        // Apple 官方跨平台加密库：macOS/iOS 上转发 CryptoKit，Linux 上独立实现——
        // CI（Linux runner 也能跑 swift test）与 App 双端一致。
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "HakoAgentKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS, .macOS], configuration: .release))]
        ),
        .testTarget(
            name: "HakoAgentKitTests",
            dependencies: ["HakoAgentKit"],
            resources: [
                .copy("Fixtures/vectors.json"),
                .copy("Fixtures/vectors-noise.json"),
            ]
        ),
    ]
)
