// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Add an extra #if checkable symbol on Big Sur, to work around a seeming Swift bug around
// #available version checks by using `#if EXTRA_WORKAROUND_FOR_BIG_SUR`.
// See eg https://developer.apple.com/forums/thread/688678 for other bug reports.
let swiftSettings: [SwiftSetting]
if #available(macOS 12, *) {
  swiftSettings = []
} else {
  swiftSettings = [.define("EXTRA_WORKAROUND_FOR_BIG_SUR")]
}

let package = Package(
  name: "vmctl",
  platforms: [
    .macOS(.v11),
  ],
  products: [
    .executable(name: "vmctl", targets: ["vmctl"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/tevelee/Tuxedo.git", from: "1.0.0"),
    .package(url: "https://github.com/mtynior/ColorizeSwift.git", from: "1.5.0"),
    .package(url: "https://github.com/JohnSundell/Files", from: "4.0.0"),
    .package(url: "https://github.com/mw99/DataCompression.git", from: "3.0.0"),
    .package(url: "https://github.com/kayembi/Tarscape", branch: "main"),
  ],
  targets: [
    .executableTarget(
      name: "vmctl",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Tuxedo", package: "Tuxedo"),
        .product(name: "ColorizeSwift", package: "ColorizeSwift"),
        .product(name: "Files", package: "Files"),
        .product(name: "DataCompression", package: "DataCompression"),
        .product(name: "Tarscape", package: "Tarscape"),
      ],
      resources: [
        .copy("templates"),
      ],
      swiftSettings: swiftSettings
    ),
  ]
)
