// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "ASMEUL", platforms: [.macOS("14.4")],
  products: [.executable(name: "ASMEUL", targets: ["ASMEUL"])],
  targets: [
    .target(
      name: "AudioCore", publicHeadersPath: "include",
      cxxSettings: [.unsafeFlags(["-std=c++17", "-fobjc-arc"])],
      linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("Foundation"), .linkedFramework("Accelerate")]),
    .executableTarget(
      name: "ASMEUL", dependencies: ["AudioCore"],
      path: "Sources/ASMEUL",
      resources: [.process("Resources")],
      linkerSettings: [
        .linkedFramework("SwiftUI"), .linkedFramework("AppKit"), .linkedFramework("Carbon"),
      ]),

  ])
