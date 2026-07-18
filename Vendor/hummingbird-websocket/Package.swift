// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "hummingbird-websocket",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "HummingbirdWebSocket", targets: ["HummingbirdWebSocket"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.25.0"),
        .package(path: "../swift-websocket"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.22.0"),
    ],
    targets: [
        .target(
            name: "HummingbirdWebSocket",
            dependencies: [
                .product(name: "WSCore", package: "swift-websocket"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "NIOHTTPTypes", package: "swift-nio-extras"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5, .version("6")]
)
