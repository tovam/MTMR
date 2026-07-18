import Foundation

enum MMTMRConfigurationLocation {
    static func canonicalURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(".mtmr.json", isDirectory: false)
    }

    static func legacyURLs(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let applicationSupport = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        return [
            applicationSupport.appendingPathComponent("MTMR/items.json", isDirectory: false),
            applicationSupport.appendingPathComponent("MTMR tovam/items.json", isDirectory: false)
        ]
    }

    static func resolveResourcePath(_ path: String, relativeTo configurationURL: URL) -> URL {
        if path == "~" || path.hasPrefix("~/") {
            let suffix = path == "~" ? "" : String(path.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(suffix)
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return configurationURL.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    }
}

struct MMTMRLaunchOptions: Equatable, Sendable {
    let configurationURL: URL
    let editorPort: Int

    static func parse(
        arguments: [String] = CommandLine.arguments,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        allowDevelopmentOverrides: Bool
    ) throws -> MMTMRLaunchOptions {
        var configurationURL = MMTMRConfigurationLocation.canonicalURL(homeDirectory: homeDirectory)
        var editorPort = 8787
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--config" || argument == "--editor-port" {
                guard allowDevelopmentOverrides else {
                    throw ConfigurationDiagnostic(
                        code: "launch.overrideDisabled",
                        message: "\(argument) is available only to tests and development launches."
                    )
                }
                guard index + 1 < arguments.count else {
                    throw ConfigurationDiagnostic(code: "launch.missingValue", message: "Missing value after \(argument).")
                }
                let value = arguments[index + 1]
                if argument == "--config" {
                    configurationURL = MMTMRConfigurationLocation.resolveResourcePath(value, relativeTo: configurationURL)
                } else {
                    guard let port = Int(value), (1...65535).contains(port) else {
                        throw ConfigurationDiagnostic(code: "launch.port", message: "Editor port must be between 1 and 65535.")
                    }
                    editorPort = port
                }
                index += 2
            } else {
                index += 1
            }
        }
        return MMTMRLaunchOptions(configurationURL: configurationURL, editorPort: editorPort)
    }
}
