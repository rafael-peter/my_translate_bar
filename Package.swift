// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Xcode runs a SwiftPM executable outside an .app. Embed the same identity
// used by the packaged application so Bundle.main still has its identifier.
let appInfoPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/AppInfo.plist").path

let package = Package(
    name: "TranslateBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "TranslateBarKit", targets: ["TranslateBarKit"]),
        .executable(name: "TranslateBar", targets: ["TranslateBar"])
    ],
    targets: [
        // Tudo que é UI/lógica fica numa library para os Previews do Xcode funcionarem.
        .target(
            name: "TranslateBarKit",
            path: "Sources/TranslateBarKit",
            resources: [
                .process("Resources")
            ]
        ),
        // O executável só contém o @main.
        .executableTarget(
            name: "TranslateBar",
            dependencies: ["TranslateBarKit"],
            path: "Sources/TranslateBarApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", appInfoPath
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "TranslateBarTests",
            dependencies: ["TranslateBarKit"],
            path: "Tests/TranslateBarTests"
        )
    ]
)
