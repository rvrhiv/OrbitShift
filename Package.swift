// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OrbitShift",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "OrbitShift", targets: ["OrbitShift"])],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
  ],
  targets: [
    .target(name: "OrbitShiftCore"),
    .executableTarget(
      name: "OrbitShift",
      dependencies: ["OrbitShiftCore", .product(name: "Sparkle", package: "Sparkle")],
      path: "App",
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]),
  ]
)
