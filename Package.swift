// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeestarKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeestarKit", targets: ["SeestarKit"]),
        .executable(name: "seestar-probe", targets: ["SeestarProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "SeestarKit",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .executableTarget(name: "SeestarProbe", dependencies: ["SeestarKit"]),
        .testTarget(
            name: "SeestarKitTests",
            dependencies: ["SeestarKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
