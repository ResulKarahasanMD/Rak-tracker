// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TrackerKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TrackerKit", targets: ["TrackerKit"]),
    ],
    targets: [
        // Pure logic, no Apple-only APIs, no dependencies. Linux-testable.
        .target(name: "TrackerKit"),
        // System SQLite, used by the test target only, so schema/migration SQL
        // can be verified against a real SQLite on any platform (incl. Linux CI).
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite"]),
            ]
        ),
        .testTarget(
            name: "TrackerKitTests",
            dependencies: ["TrackerKit", "CSQLite"]
        ),
    ]
)
