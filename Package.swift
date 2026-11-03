// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorLocalGeofence",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorLocalGeofence",
            targets: ["LocalGeofencePlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "LocalGeofencePlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/LocalGeofencePlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(
            name: "LocalGeofencePluginTests",
            dependencies: ["LocalGeofencePlugin"],
            path: "ios/Tests/LocalGeofencePluginTests")
    ]
)