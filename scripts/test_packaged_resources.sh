#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibecast-resources-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/main.swift" <<'SWIFT'
import Foundation

extension Bundle {
    static var module: Bundle { fatalError("An installed app accessed the development bundle") }
}
let fm = FileManager.default
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
func write(_ text: String, _ path: URL) throws {
    try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: path)
}
func makeApp(_ name: String) throws -> URL {
    let app = fixtures.appendingPathComponent(name + ".app")
    let info: [String: Any] = ["CFBundleIdentifier": "test.vibecast." + name, "CFBundlePackageType": "APPL", "CFBundleName": name]
    let infoURL = app.appendingPathComponent("Contents/Info.plist")
    try fm.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
    return app
}
for layout in ["nested", "flat", "direct"] {
    let app = try makeApp(layout)
    let resources = app.appendingPathComponent("Contents/Resources")
    let web: URL
    if layout == "nested" {
        let bundle = resources.appendingPathComponent("VibeCast_VibeCast.bundle")
        let info: [String: Any] = ["CFBundleIdentifier": "test.vibecast.resources", "CFBundlePackageType": "BNDL"]
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        web = bundle.appendingPathComponent("Contents/Resources/web")
    } else if layout == "flat" {
        web = resources.appendingPathComponent("VibeCast_VibeCast.bundle/web")
    } else {
        web = resources.appendingPathComponent("web")
    }
    try write("<script type=\"module\" src=\"./assets/main.js\"></script>", web.appendingPathComponent("index.html"))
    try write("config", web.appendingPathComponent("config.html"))
    try write("document.title='loaded';", web.appendingPathComponent("assets/main.js"))
    try write("body{color:black}", web.appendingPathComponent("assets/main.css"))
    guard let bundle = Bundle(url: app),
          let server = StaticFileServer(appBundle: bundle, developmentWebRoot: { fatalError("Unexpected fallback") }) else {
        fatalError("Failed to find packaged resources for \(layout)")
    }
    for path in ["/", "/config.html", "/assets/main.js", "/assets/main.css"] {
        precondition(server.resolve(path: path) != nil, "Missing packaged asset: \(layout) \(path)")
    }
}
let broken = try makeApp("incomplete")
let brokenWeb = broken.appendingPathComponent("Contents/Resources/web")
try write("index only", brokenWeb.appendingPathComponent("index.html"))
try write("config", brokenWeb.appendingPathComponent("config.html"))
precondition(StaticFileServer(appBundle: Bundle(url: broken)!, developmentWebRoot: { fatalError("Unexpected fallback") }) == nil)
print("PASS: nested, flat, direct packaged resources; incomplete app rejected; no development bundle access")
SWIFT
swiftc -O -module-cache-path "${VIBECAST_MODULE_CACHE:-$TEST_DIR/module-cache}" \
  "$ROOT/mac/Sources/VibeCast/Server/StaticFileServer.swift" \
  "$ROOT/mac/Sources/VibeCast/Server/HTTPRequest.swift" \
  "$TEST_DIR/main.swift" -o "$TEST_DIR/test-resources"
"$TEST_DIR/test-resources" "$TEST_DIR/fixtures"
