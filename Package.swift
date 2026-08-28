// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "AltSign",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],

    products: [
        .library(
            name: "AltSign-Static",
            type: .static,
            targets: ["AltSign"]
        ),
        .library(
            name: "AltSign-Dynamic",
            type: .dynamic,
            targets: ["AltSign"]
        )
    ],

    dependencies: [
        .package(url: "https://github.com/mahee96/CodeSignKit.git",  branch: "main"),
        .package(url: "https://github.com/mahee96/GSACryptoKit.git", branch: "main"),
        .package(url: "https://github.com/SideStore/minizip-ng",     branch: "develop")

//        .package(name: "CodeSignKit",  path: "../../local/CodeSignKit"),
//        .package(name: "GSACryptoKit", path: "../../local/GSACryptoKit"),
//        .package(name: "minizip-ng",   path: "../minizip-ng")
    ],

    targets: [
        // ─────────────────────────
        // Main Swift target
        // ─────────────────────────
        .target(
            name: "AltSign",
            dependencies: [
                .product(name: "minizip-ng", package: "minizip-ng"),
                "CodeSignKit",
                "GSACryptoKit"
            ],

            path: "Sources",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
            ]
        )
    ],

    cLanguageStandard: .gnu11
)
