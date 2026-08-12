// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeestarKit",
    // L'anglais est la langue de repli : c'est elle qui s'affiche quand la
    // langue du système n'est pas traduite.
    defaultLocalization: "en",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeestarKit", targets: ["SeestarKit"]),
        .library(name: "SeestarUI", targets: ["SeestarUI"]),
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
        .target(
            name: "SeestarUI",
            dependencies: ["SeestarKit"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "SeestarProbe", dependencies: ["SeestarKit"]),
        .testTarget(
            name: "SeestarKitTests",
            dependencies: ["SeestarKit", "SeestarUI"],
            resources: [.copy("Fixtures")]
        )
    ]
)
