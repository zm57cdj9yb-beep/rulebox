// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RuleBox",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RuleBoxCore", targets: ["RuleBoxCore"]),
        .executable(name: "RuleBox", targets: ["RuleBox"]),
        .executable(name: "RuleBoxBench", targets: ["RuleBoxBench"])
    ],
    targets: [
        .target(
            name: "RuleBoxCore",
            path: "Sources/RuleBoxCore",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "RuleBox",
            dependencies: ["RuleBoxCore"],
            path: "Sources/RuleBox",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "RuleBoxBench",
            dependencies: ["RuleBoxCore"],
            path: "benchmarks/swift-bench"
        ),
        .testTarget(
            name: "RuleBoxCoreTests",
            dependencies: ["RuleBoxCore"],
            path: "Tests/RuleBoxCoreTests"
        )
    ]
)
