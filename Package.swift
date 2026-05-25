// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SyntaxEditorUI",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SyntaxEditorUI",
            targets: ["SyntaxEditorUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-objc", from: "3.0.2"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-xml", exact: "0.7.0"),
        .package(url: "https://github.com/lynnswap/tree-sitter-swift", exact: "0.1.0"),
        .package(url: "https://github.com/lynnswap/ObservationBridge", exact: "0.9.1"),
    ],
    targets: [
        .target(
            name: "XclangSpecSyntax",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(nil),
                .strictMemorySafety(),
            ]
        ),
        .target(
            name: "SourceModelBridge",
            path: "Sources/SourceModelBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "EditorSpecTool",
            dependencies: [
                "SourceModelBridge",
                "SyntaxEditorCore",
            ],
            path: "Tools/EditorSpecSnapshot/EditorSpecTool",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(nil),
                .strictMemorySafety(),
                .unsafeFlags([
                    "-I", "Tools/EditorSpecSnapshot/PrivateInterfaces",
                    "-F", "/Applications/Xcode.app/Contents/SharedFrameworks",
                ], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Applications/Xcode.app/Contents/SharedFrameworks",
                    "-framework", "SourceEditor",
                    "-framework", "SymbolCache",
                    "-framework", "SymbolCacheIndexing",
                    "-framework", "SymbolCacheSupport",
                    "/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCache.framework/Versions/A/SymbolCache",
                    "/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheIndexing.framework/Versions/A/SymbolCacheIndexing",
                    "/Applications/Xcode.app/Contents/SharedFrameworks/SymbolCacheSupport.framework/Versions/A/SymbolCacheSupport",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Applications/Xcode.app/Contents/SharedFrameworks",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "SyntaxEditorCore",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterObjc", package: "tree-sitter-objc"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                .product(name: "TreeSitterXML", package: "tree-sitter-xml"),
            ],
            resources: [
                .copy("Resources/CSSQueries"),
                .copy("Resources/HTMLQueries"),
                .copy("Resources/JavaScriptQueries"),
                .copy("Resources/JSONQueries"),
                .copy("Resources/ObjectiveCQueries"),
                .copy("Resources/SwiftQueries"),
                .copy("Resources/TOMLQueries"),
                .copy("Resources/XMLQueries"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(nil),
                .strictMemorySafety(),
            ]
        ),
        .target(
            name: "SyntaxEditorUI",
            dependencies: [
                "SyntaxEditorCore",
                .product(name: "ObservationBridge", package: "observationbridge"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(nil),
                .strictMemorySafety(),
            ]
        ),
        .testTarget(
            name: "SyntaxEditorCoreTests",
            dependencies: ["SyntaxEditorCore"]
        ),
        .testTarget(
            name: "XclangSpecSyntaxTests",
            dependencies: ["XclangSpecSyntax"]
        ),
        .testTarget(
            name: "SyntaxEditorCorePlatformTests",
            dependencies: ["SyntaxEditorCore"]
        ),
        .testTarget(
            name: "SyntaxEditorUITests",
            dependencies: ["SyntaxEditorUI"]
        ),
    ]
)
