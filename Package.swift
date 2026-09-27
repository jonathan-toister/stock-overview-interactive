// swift-tools-version:5.9
import PackageDescription

// PortfolioCore downloads and reads the IBKR report and fetches Yahoo prices;
// Portfolio is the SwiftUI app; portfolio-check is a small command-line tool
// for checking PortfolioCore against a saved report, Yahoo, or a live download.
let package = Package(
    name: "Portfolio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Portfolio", targets: ["Portfolio"]),
        .executable(name: "portfolio-check", targets: ["portfolio-check"]),
    ],
    targets: [
        .target(name: "PortfolioCore"),
        .executableTarget(name: "Portfolio", dependencies: ["PortfolioCore"]),
        .executableTarget(name: "portfolio-check", dependencies: ["PortfolioCore"]),
    ]
)
