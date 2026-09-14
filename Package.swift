// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "Hollow", platforms: [.macOS("14.4")],
  products: [.executable(name: "Hollow", targets: ["Hollow"])],
  targets: [
    .target(
      name: "AudioCore", publicHeadersPath: "include",
      cxxSettings: [.unsafeFlags(["-std=c++17", "-fobjc-arc"])],
      linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("Foundation"), .linkedFramework("Accelerate")]),
    .executableTarget(
      name: "Hollow", dependencies: ["AudioCore"],
      path: "Sources/ASMEUL",
      resources: [.process("Resources")],
      linkerSettings: [
        .linkedFramework("SwiftUI"), .linkedFramework("AppKit"), .linkedFramework("Carbon"),
      ]),

  ])
