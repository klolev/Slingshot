// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Slingshot",
    platforms: [.macOS(.v10_15), .iOS(.v16)],
    products: [
        .library(
            name: "Slingshot",
            targets: ["Slingshot"]),
    ],
    targets: [
        .target(name: "Slingshot"),
        .plugin(name: "SlingshotPlugin", 
                capability: .command(intent: .custom(verb: "generate-slingshot",
                                                     description: "generate code"),
                                     permissions: [.writeToPackageDirectory(reason: "Yeeting the universe")])),
        .testTarget(
            name: "SlingshotTests",
            dependencies: ["Slingshot"],
            path: "Tests"),
    ]
)
