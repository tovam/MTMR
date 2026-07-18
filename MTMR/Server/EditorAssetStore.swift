import Foundation

struct ServerEditorAsset: Equatable, Sendable {
    let data: Data
    let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
}

protocol ServerEditorAssetServing: Sendable {
    func asset(at path: String) -> ServerEditorAsset?
}

/// Reads only files contained by the bundled `Editor` directory.
struct BundleEditorAssetStore: ServerEditorAssetServing, Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    init?(bundle: Bundle = .main, subdirectory: String = "Editor") {
        guard let resources = bundle.resourceURL else { return nil }
        self.init(rootURL: resources.appendingPathComponent(subdirectory, isDirectory: true))
    }

    func asset(at path: String) -> ServerEditorAsset? {
        guard Self.isSafeRelativePath(path) else { return nil }

        let candidate = rootURL
            .appendingPathComponent(path, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath), candidate.isFileURL else { return nil }
        guard let data = try? Data(contentsOf: candidate, options: [.mappedIfSafe]) else { return nil }

        return ServerEditorAsset(data: data, contentType: Self.contentType(for: candidate.pathExtension))
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func contentType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "json", "webmanifest":
            return "application/json; charset=utf-8"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "map":
            return "application/json; charset=utf-8"
        default:
            return "application/octet-stream"
        }
    }
}
