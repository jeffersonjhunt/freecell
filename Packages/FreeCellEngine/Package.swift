// swift-tools-version: 6.0
import PackageDescription

// The FreeCell rules as a value-type library with no SwiftUI import, so every rule is testable
// without a view — on Apple platforms and on Linux alike.
let package = Package(
    name: "FreeCellEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FreeCellEngine", targets: ["FreeCellEngine"]),
    ],
    targets: [
        .target(name: "FreeCellEngine"),
        .testTarget(name: "FreeCellEngineTests", dependencies: ["FreeCellEngine"]),
    ]
)
