// 从打包资源 Resources/web 提供前端静态文件。含路径穿越防护。

import Foundation

struct StaticFileServer {
    let webRoot: URL

    init?(appBundle: Bundle = .main,
          developmentWebRoot: () -> URL? = { Bundle.module.url(forResource: "web", withExtension: nil) }) {
        if let resources = appBundle.resourceURL {
            let nestedURL = resources.appendingPathComponent("VibeCast_VibeCast.bundle", isDirectory: true)
            let candidates = [
                // A macOS resource bundle stores files in Contents/Resources.
                Bundle(url: nestedURL)?.url(forResource: "web", withExtension: nil),
                nestedURL.appendingPathComponent("web", isDirectory: true),
                resources.appendingPathComponent("web", isDirectory: true)
            ].compactMap { $0 }
            if let root = candidates.first(where: Self.isCompleteWebRoot) {
                self.webRoot = root
                return
            }
        }

        // SwiftPM's generated Bundle.module accessor embeds the temporary build
        // path and may fatalError. An installed app must never depend on it.
        guard appBundle.bundleURL.pathExtension != "app",
              let root = developmentWebRoot(), Self.isCompleteWebRoot(root) else { return nil }
        self.webRoot = root
    }

    private static func isCompleteWebRoot(_ root: URL) -> Bool {
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: root.appendingPathComponent("index.html").path),
              manager.isReadableFile(atPath: root.appendingPathComponent("config.html").path),
              let assets = try? manager.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path) else {
            return false
        }
        return assets.contains(where: { $0.hasSuffix(".js") }) && assets.contains(where: { $0.hasSuffix(".css") })
    }

    init(webRoot: URL) {
        self.webRoot = webRoot
    }

    enum RouteMode {
        case all
        case phone
        case config
    }

    /// 解析请求路径到文件数据 + MIME。找不到返回 nil。
    func resolve(path: String, mode: RouteMode = .all) -> (data: Data, contentType: String)? {
        var rel = path
        if rel == "/" { rel = "/index.html" }
        guard allows(rel, mode: mode) else { return nil }
        // 去掉前导斜杠并规整。
        let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel

        let root = webRoot.standardizedFileURL
        let candidate = webRoot.appendingPathComponent(cleaned).standardizedFileURL
        // 路径穿越防护：必须仍在 webRoot 之内。
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }
        guard let data = try? Data(contentsOf: candidate) else { return nil }
        return (data, HTTPResponse.mimeType(forPath: candidate.lastPathComponent))
    }

    private func allows(_ path: String, mode: RouteMode) -> Bool {
        switch mode {
        case .all:
            return true
        case .phone:
            return path != "/config.html"
        case .config:
            return path != "/index.html"
        }
    }
}
