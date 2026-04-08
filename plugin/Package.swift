// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "SampleChain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SampleChainApp", targets: ["SampleChainApp"]),
        .library(name: "SampleChainAU", targets: ["SampleChainAU"]),
        .library(name: "SampleChainDSP", targets: ["SampleChainDSP"]),
        .library(name: "SampleChainUI", targets: ["SampleChainUI"]),
        .library(name: "SampleChainCore", targets: ["SampleChainCore"]),
    ],
    targets: [
        // MARK: - Core: shared models, networking, caching, auth, blockchain
        .target(
            name: "SampleChainCore",
            dependencies: [],
            path: "Sources/SampleChainCore"
        ),

        // MARK: - DSP: audio engine, analysis, offline rendering
        .target(
            name: "SampleChainDSP",
            dependencies: ["SampleChainCore"],
            path: "Sources/SampleChainDSP",
            linkerSettings: [
                // Rubberband C library expected to be installed via Homebrew or vendored
                .linkedLibrary("rubberband"),
                .unsafeFlags(["-L/opt/homebrew/lib", "-L/usr/local/lib"]),
            ]
        ),

        // MARK: - UI: shared SwiftUI views and theme
        .target(
            name: "SampleChainUI",
            dependencies: ["SampleChainCore", "SampleChainDSP"],
            path: "Sources/SampleChainUI"
        ),

        // MARK: - AU: AUv3 audio unit plugin
        .target(
            name: "SampleChainAU",
            dependencies: ["SampleChainCore", "SampleChainDSP", "SampleChainUI"],
            path: "Sources/SampleChainAU"
        ),

        // MARK: - App: standalone macOS host application
        .executableTarget(
            name: "SampleChainApp",
            dependencies: ["SampleChainCore", "SampleChainDSP", "SampleChainUI", "SampleChainAU"],
            path: "Sources/SampleChainApp"
        ),
    ]
)
