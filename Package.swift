// swift-tools-version:5.9
import PackageDescription

// One-way dependencies: LiteKey (app) → LiteKeyPlatform → LiteKeyCore → LiteKeyEngine.
// LiteKeyEngine and LiteKeyCore are pure Swift and build and test on Linux.
// LiteKeyPlatform and the app need AppKit, so they are declared only on macOS: `swift test` builds
// every target in the package, and hiding them lets
// `swift test --filter "LiteKeyEngineTests|LiteKeyCoreTests"` run on Linux.

var products: [Product] = [
    .library(name: "LiteKeyEngine", targets: ["LiteKeyEngine"]),
    .library(name: "LiteKeyCore", targets: ["LiteKeyCore"]),
]

var targets: [Target] = [
    // Pure Swift Vietnamese typing engine
    .target(
        name: "LiteKeyEngine",
        path: "Sources/LiteKeyEngine"
    ),
    .target(
        name: "LiteKeyCore",
        dependencies: ["LiteKeyEngine"],
        path: "Sources/LiteKeyCore"
    ),
    .testTarget(
        name: "LiteKeyEngineTests",
        dependencies: ["LiteKeyEngine"],
        path: "Tests/LiteKeyEngineTests"
    ),
    .testTarget(
        name: "LiteKeyCoreTests",
        dependencies: ["LiteKeyCore"],
        path: "Tests/LiteKeyCoreTests"
    ),
]

#if os(macOS)
products.append(.library(name: "LiteKeyPlatform", targets: ["LiteKeyPlatform"]))
targets += [
    // Thin macOS layer: event tap, event normalization, key injection, Accessibility permission
    .target(
        name: "LiteKeyPlatform",
        dependencies: ["LiteKeyCore"],
        path: "Sources/LiteKeyPlatform",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("ServiceManagement"),
        ]
    ),
    // Menu bar app: composition root and UI
    .executableTarget(
        name: "LiteKey",
        dependencies: ["LiteKeyEngine", "LiteKeyCore", "LiteKeyPlatform"],
        path: "Sources/LiteKey",
        linkerSettings: [
            .linkedFramework("AppKit"),
        ]
    ),
]
#endif

let package = Package(
    name: "LiteKey",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
