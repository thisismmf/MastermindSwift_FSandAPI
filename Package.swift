// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mastermind",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "mastermind", targets: ["Mastermind"]),
    ],
    targets: [
        .executableTarget(
            name: "Mastermind",
            path: "Sources/Mastermind"
        )
    ]
)