// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Slingshot",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(
            name: "Slingshot",
            targets: ["Slingshot"]),
    ],
    traits: [
        .trait(name: "Macros", description: "#do notation. Builds swift-syntax, so it's off by default."),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", "602.0.0"..<"605.0.0"),
    ],
    targets: [
        .target(name: "Slingshot",
                dependencies: [
                    .target(name: "SlingshotMacros", condition: .when(traits: ["Macros"])),
                ],
                exclude: ["CodeGeneration/Templates", "CodeGeneration/config.json"]),
        .macro(name: "SlingshotMacros",
               dependencies: [
                   .product(name: "SwiftSyntax", package: "swift-syntax"),
                   .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                   .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                   .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                   .product(name: "SwiftDiagnostics", package: "swift-syntax"),
               ]),
        .plugin(name: "SlingshotPlugin",
                capability: .command(intent: .custom(verb: "generate-slingshot",
                                                     description: "generate code"),
                                     permissions: [.writeToPackageDirectory(reason: "Yeeting the universe")])),
        .testTarget(
            name: "SlingshotTests",
            dependencies: [
                "Slingshot",
                .target(name: "SlingshotMacros", condition: .when(traits: ["Macros"])),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax", condition: .when(traits: ["Macros"])),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax", condition: .when(traits: ["Macros"])),
            ],
            path: "Tests"),
    ]
)
