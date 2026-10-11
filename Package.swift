// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickTextProcessor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure logic: models, stores, prompt templating, provider wire formats.
        // No AppKit/AX imports so `swift test` runs on any macOS box (incl. CI).
        .target(
            name: "QTPCore"
        ),
        // The macOS app: SwiftUI + AppKit, hotkey, accessibility, panels, OAuth.
        .executableTarget(
            name: "QuickTextProcessor",
            dependencies: ["QTPCore"],
            resources: [
                .copy("Resources/oauth_success.html"),
                .copy("Resources/codex_instructions.md"),
            ]
        ),
        .testTarget(
            name: "QTPCoreTests",
            dependencies: ["QTPCore"]
        ),
    ]
)
