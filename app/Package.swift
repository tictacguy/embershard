// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Resolve the engine build directory at manifest-evaluation time so the path
// is always absolute — works from Xcode, `swift build`, or `make_dmg.sh`.
// Override by setting EMBERSHARD_BUILD=/path/to/build before running swift build.
let buildDir: String = {
    if let env = ProcessInfo.processInfo.environment["EMBERSHARD_BUILD"] {
        return env
    }
    return URL(fileURLWithPath: #file)         // …/app/Package.swift
        .deletingLastPathComponent()           // …/app/
        .appendingPathComponent("../build")   // …/app/../build
        .standardized.path                    // …/embershard/build
}()

let package = Package(
    name: "Embershard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Embershard", targets: ["EmberShardApp"]),
    ],
    targets: [
        // Thin C shim: exposes es_api.h to Swift.
        // The real symbols live in libembershard_engine.a + libllama dylibs,
        // linked via unsafeFlags pointing to buildDir.
        .target(
            name: "EmberShardBridge",
            path: "Sources/EmberShardBridge",
            publicHeadersPath: "include",
            cSettings: [],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(buildDir)",
                    "-L\(buildDir)/bin",
                    "-lembershard_engine",
                    "-lllama",
                    "-lggml",
                    "-lggml-metal",
                    "-lggml-blas",
                    "-lggml-cpu",
                    "-lggml-base",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", buildDir,
                    "-Xlinker", "-rpath", "-Xlinker", "\(buildDir)/bin",
                ]),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
            ]
        ),

        // SwiftUI macOS application
        .executableTarget(
            name: "EmberShardApp",
            dependencies: ["EmberShardBridge"],
            path: "Sources/EmberShardApp",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/ProviderIcons"),
                .process("Resources/logo.svg"),
            ]
        ),
    ]
)
