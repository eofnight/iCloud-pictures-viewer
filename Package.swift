// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CloudLens", platforms: [.macOS(.v14)], products: [.executable(name: "CloudLens", targets: ["CloudLens"])], targets: [.executableTarget(name: "CloudLens")], swiftLanguageModes: [.v5])
