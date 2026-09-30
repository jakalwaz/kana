// swift-tools-version: 6.0
//
// Kana is built with SwiftPM so it works with just the Command Line Tools.
// `script/build` wraps the executable into Kana.app.

import PackageDescription

let package = Package(
    name: "Kana",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned exactly. Bump on purpose: it moves the Ghostty revision too
        // (1.6.20260929 = Ghostty 0538f7535be0).
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.6.20260929"),
        .package(path: "Packages/KanaSkins"),
    ],
    targets: [
        .executableTarget(
            name: "Kana",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "KanaSkins", package: "KanaSkins"),
                "KanaCore",
            ],
            path: "App",
            resources: [.copy("Shell/zsh")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Pure logic the app uses (split layout, config, fuzzy matching): no
        // AppKit, no libghostty, so it's unit tested.
        .target(
            name: "KanaCore",
            path: "Core",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The welcome screen, shared by the `kana` command and its tests.
        .target(
            name: "KanaBanner",
            dependencies: [.product(name: "KanaSkins", package: "KanaSkins")],
            path: "CLI/KanaBanner"
        ),
        // `kana`, the helper command. Named kana-cli here because the default
        // macOS disk ignores case and `kana` would collide with `Kana`;
        // script/build installs it as Kana.app/Contents/Resources/bin/kana.
        .executableTarget(
            name: "kana-cli",
            dependencies: ["KanaBanner", .product(name: "KanaSkins", package: "KanaSkins")],
            path: "CLI/kana"
        ),
        .testTarget(
            name: "KanaCoreTests",
            dependencies: ["KanaCore"],
            path: "Tests/KanaCoreTests"
        ),
        .testTarget(
            name: "KanaBannerTests",
            dependencies: ["KanaBanner", .product(name: "KanaSkins", package: "KanaSkins")],
            path: "Tests/KanaBannerTests"
        ),
    ]
)
