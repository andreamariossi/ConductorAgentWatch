// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ConductorAgentWatch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ConductorAgentWatch", targets: ["ConductorAgentWatch"])
    ],
    targets: [
        .executableTarget(
            name: "ConductorAgentWatch",
            path: "Sources/ConductorAgentWatch",
            resources: [.process("Resources")]
        )
    ]
)
