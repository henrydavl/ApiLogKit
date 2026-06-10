// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ApiLogKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "ApiLogKit", targets: ["ApiLogKit"]),
    ],
    targets: [
        .target(name: "ApiLogKit"),
    ]
)
