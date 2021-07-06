// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HiFiSpatialAudio",
    platforms: [
        .iOS(.v10)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "HiFiSpatialAudio",
            targets: ["HiFiSpatialAudio"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "Promises", url: "https://github.com/google/promises.git", from: "1.2.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "4.0.0")),
        .package(name: "Gzip", url: "https://github.com/1024jp/GzipSwift.git", .upToNextMajor(from: "5.1.1")),
        // Uncomment the line below to use High Fidelity's custom WebRTC build (may have added features like stereo support).
        .package(name: "WebRTC", url: "https://github.com/highfidelity/HiFi-WebRTC-iOS.git", .branch("main"))
        // Uncomment the line below to use Google's M85 WebRTC build (older but quite stable).
        //.package(name: "WebRTC", url: "https://github.com/alexpiezo/WebRTC.git", .upToNextMajor(from: "1.1.31567"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "HiFiSpatialAudio",
            dependencies: ["WebRTC", "Gzip", "Promises", "Starscream"])
    ]
)
