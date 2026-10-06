// swift-tools-version: 6.0
import PackageDescription

// Features shipped in the app, by folder name in Features/.
// Adding one: copy Features/_Template to Features/<Name>, add "<Name>" here and register it in
// Features/Registry. Removing one: delete its folder and those lines — everything else must still build.
let features: [String] = ["Clipboard", "Home", "Shelf", "Tasks", "Timer"]

let composableArchitecture: Target.Dependency = .product(
  name: "ComposableArchitecture",
  package: "swift-composable-architecture"
)
let keyboardShortcuts: Target.Dependency = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")

/// Every feature depends on this base and nothing else — never on another feature.
let featureBase: [Target.Dependency] = ["VortexCore", "VortexPlatform", composableArchitecture, grdb]

let featureTargets: [Target] = features.flatMap { name -> [Target] in
  [
    .target(
      name: "Feature\(name)",
      dependencies: featureBase,
      path: "Features/\(name)/Sources",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "Feature\(name)Tests",
      dependencies: [.target(name: "Feature\(name)")] + featureBase,
      path: "Features/\(name)/Tests"
    ),
  ]
}

let package = Package(
  name: "VortexKit",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "VortexShell", targets: ["VortexShell"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2"),
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
  ],
  targets: [
    .target(
      name: "VortexCore",
      dependencies: [composableArchitecture, grdb],
      path: "Core/Sources",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "VortexCoreTests",
      dependencies: ["VortexCore", grdb],
      path: "Core/Tests"
    ),
    .target(
      name: "VortexPlatform",
      dependencies: ["VortexCore", composableArchitecture, keyboardShortcuts],
      path: "Platform/Sources"
    ),
    .testTarget(
      name: "VortexPlatformTests",
      dependencies: ["VortexPlatform", composableArchitecture],
      path: "Platform/Tests"
    ),
    .target(
      name: "VortexShell",
      dependencies: ["VortexCore", "VortexPlatform", "FeatureRegistry", composableArchitecture],
      path: "Shell/Sources",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "VortexShellTests",
      dependencies: ["VortexShell", composableArchitecture],
      path: "Shell/Tests"
    ),
    .target(
      name: "FeatureRegistry",
      dependencies: ["VortexCore"] + features.map { Target.Dependency.target(name: "Feature\($0)") },
      path: "Features/Registry/Sources"
    ),
    .target(
      name: "FeatureTemplate",
      dependencies: featureBase,
      path: "Features/_Template/Sources",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "FeatureTemplateTests",
      dependencies: ["FeatureTemplate"] + featureBase,
      path: "Features/_Template/Tests"
    ),
  ] + featureTargets
)
