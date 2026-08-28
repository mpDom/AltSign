// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "AltSign",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],

    products: [
        .library(
            name: "AltSign",
            type: .static,
            targets: ["AltSign"]
        ),
        .library(
            name: "AltSign-Dynamic",
            type: .dynamic,
            targets: ["AltSign"]
        ),
    ],

    dependencies: [
        .package(url: "https://github.com/mahee96/CodeSignKit.git",  branch: "main"),
        .package(url: "https://github.com/mahee96/GSACryptoKit.git", branch: "main"),
        .package(url: "https://github.com/SideStore/minizip-ng",     branch: "develop"),
        .package(url: "https://github.com/mahee96/AnisetteKit.git",   branch: "main"),

//        .package(name: "CodeSignKit",  path: "../../local/CodeSignKit"),
//        .package(name: "GSACryptoKit", path: "../../local/GSACryptoKit"),
//        .package(name: "minizip-ng",   path: "../../local/minizip-ng")
//        .package(name: "minizip-ng",   path: "../../local/AnisetteKit")
    ],

    targets: [
        .target(
            name: "AltSign",
            dependencies: [
                .product(name: "minizip-ng", package: "minizip-ng"),
                "AnisetteKit",
                "CodeSignKit",
                "GSACryptoKit"
            ],

            path: "Sources",
        )
    ],

    cLanguageStandard: .gnu11
)
