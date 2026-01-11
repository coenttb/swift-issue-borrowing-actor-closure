// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "BorrowingActorClosure",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BorrowingActorClosure", targets: ["BorrowingActorClosure"]),
    ],
    targets: [
        .target(name: "BorrowingActorClosure")
    ],
    swiftLanguageModes: [.v6]
)
