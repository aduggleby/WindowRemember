// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WindowRemember", platforms: [.macOS(.v14)], products: [.executable(name: "WindowRemember", targets: ["WindowRemember"])], targets: [.executableTarget(name: "WindowRemember")])
