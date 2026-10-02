// swift-tools-version: 6.0
import PackageDescription

// Features shipped in the app, by folder name in Features/.
// Adding one: copy Features/_Template to Features/<Name>, add "<Name>" here and register it in
// Features/Registry. Removing one: delete its folder and those two lines — everything else must still build.
let features: [String] = []

let composableArchitecture: Target.Dependency = .product(
  name: "ComposableArchitecture",
  package: "swift-composable-architecture"
)

/// Every feature depends on this base and nothing else — never on another feature.
let featureBase: [Target.Dependency] = ["VortexCore", "VortexPlatform", composableArchitecture]

let featureTargets: [Target] = features.flatMap { name -> [Target] in
  [
    .target(
      name: "Feature\(name)",
      dependencies: featureBase,
      path: "Features/\(name)/Sources"
    ),
    .testTarget(
      name: "Feature\(name)Tests",
      dependencies: [.target(name: "Feature\(name)"), composableArchitecture],
      path: "Features/\(name)/Tests"
    ),
  ]
}

let package = Package(
  name: "VortexKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "VortexCore", targets: ["VortexCore"]),
    .library(name: "FeatureRegistry", targets: ["FeatureRegistry"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2"),
  ],
  targets: [
    .target(
      name: "VortexCore",
      path: "Core/Sources"
    ),
    .target(
      name: "VortexPlatform",
      dependencies: ["VortexCore", composableArchitecture],
      path: "Platform/Sources"
    ),
    .target(
      name: "FeatureRegistry",
      dependencies: ["VortexCore"] + features.map { Target.Dependency.target(name: "Feature\($0)") },
      path: "Features/Registry/Sources"
    ),
    .target(
      name: "FeatureTemplate",
      dependencies: featureBase,
      path: "Features/_Template/Sources"
    ),
    .testTarget(
      name: "FeatureTemplateTests",
      dependencies: ["FeatureTemplate", composableArchitecture],
      path: "Features/_Template/Tests"
    ),
  ] + featureTargets
)
