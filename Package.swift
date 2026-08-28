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
        ),
        .library(
            name: "OpenSSL",
            targets: ["OpenSSL"]
        )
    ],

    dependencies: [
        .package(url: "https://github.com/mahee96/CodeSignKit.git", branch: "main"),
        .package(url: "https://github.com/mahee96/GSACryptoKit.git", branch: "main")

//        .package(name: "CodeSignKit",  path: "../../local/CodeSignKit"),
//        .package(name: "GSACryptoKit", path: "../../local/GSACryptoKit")
    ],

    targets: [
        .binaryTarget(
            name: "OpenSSL",
            url: "https://github.com/krzyzanowskim/OpenSSL/releases/download/3.6.2000/OpenSSL.xcframework.zip",
            checksum: "37846a8bd302cb2443eff47f1045ab844d0cd40bf82cc6159cfad9aa5c3eff9e"
        ),

        // ─────────────────────────
        // C / C++ bridge
        // ─────────────────────────
        .target(
            name: "NativeBridge",
            dependencies: [
            ],
            path: ".",
            sources: [
                "NativeBridge/Sources",
                
                "Dependencies/minizip-ng/mz_crypt.c",
                "Dependencies/minizip-ng/mz_crypt_apple.c",
                "Dependencies/minizip-ng/mz_os.c",
                "Dependencies/minizip-ng/mz_os_posix.c",
                "Dependencies/minizip-ng/mz_strm.c",
                "Dependencies/minizip-ng/mz_strm_buf.c",
                "Dependencies/minizip-ng/mz_strm_mem.c",
                "Dependencies/minizip-ng/mz_strm_os_posix.c",
                "Dependencies/minizip-ng/mz_strm_pkcrypt.c",
                "Dependencies/minizip-ng/mz_strm_split.c",
                "Dependencies/minizip-ng/mz_strm_wzaes.c",
                "Dependencies/minizip-ng/mz_strm_zlib.c",
                "Dependencies/minizip-ng/mz_zip.c",
                "Dependencies/minizip-ng/mz_zip_rw.c",
            ],

            publicHeadersPath: "NativeBridge/include",

            cSettings: [
                .headerSearchPath("NativeBridge/include"),
                .headerSearchPath("Dependencies/minizip-ng"),

                .define("unix", to: "1"),
                .define("HAVE_ZLIB", to: "1"),
                .define("ZLIB_COMPAT", to: "1"),
                .define("HAVE_WZAES", to: "1"),
                .define("HAVE_PKCRYPT", to: "1"),
                .define("NOCRYPT"),
                .define("NOUNCRYPT"),

                .unsafeFlags(["-w", "-fvisibility=hidden"])
            ],

            cxxSettings: [
                .headerSearchPath("NativeBridge/include"),
                .unsafeFlags(["-w", "-fvisibility=hidden"])
            ],

            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),

        // ─────────────────────────
        // Main Swift target
        // ─────────────────────────
        .target(
            name: "AltSign",
            dependencies: [
                "NativeBridge",
                "OpenSSL",
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
