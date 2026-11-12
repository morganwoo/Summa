// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SummaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SummaCore", targets: ["SummaCore"])],
    targets: [
        .target(name: "SummaCore"),
        .testTarget(name: "SummaCoreTests", dependencies: ["SummaCore"]),
    ]
)
