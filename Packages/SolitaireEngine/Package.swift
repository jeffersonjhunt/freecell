// swift-tools-version: 6.0
import PackageDescription

// The Klondike rules as a value-type library with no SwiftUI import, so every rule is testable
// without a view — on Apple platforms and on Linux alike.
let package = Package(
    name: "SolitaireEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SolitaireEngine", targets: ["SolitaireEngine"]),
    ],
    targets: [
        .target(name: "SolitaireEngine"),
        .testTarget(name: "SolitaireEngineTests", dependencies: ["SolitaireEngine"]),
    ]
)
