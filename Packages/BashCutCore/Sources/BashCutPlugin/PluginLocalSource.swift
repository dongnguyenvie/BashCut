import Foundation

/// What "Add Plugin…" was given: a plugin folder, a zip (`.zip` or `.bashcutplugin`) with one plugin folder, or
/// the folder's `plugin.json`.
public enum PluginLocalSourceKind: String, Sendable {
    case folder, archive, manifest
}

/// What `plugins validate` reports about a folder, zip or `plugin.json`: the manifest when it reads, and every
/// problem that would stop the install. Nothing in the plugin runs.
public struct PluginValidation: Sendable {
    public var kind: PluginLocalSourceKind?
    public var manifest: PluginManifest?
    /// Reasons the plugin cannot be added, each naming the field or file and the fix.
    public var problems: [String] = []
    /// Things that do not stop the install, such as an unknown category.
    public var warnings: [String] = []
    /// SHA-256 of the archive, for zips.
    public var sha256: String?
    public var isValid: Bool { manifest != nil && problems.isEmpty }

    public init() {}
}

/// A local plugin copied into a staging folder and checked, waiting for the user's approval. The copy is what gets
/// installed, so later edits to the source do not slip in between approval and install.
public struct StagedLocalPlugin: Sendable {
    public let plugin: InstalledPlugin
    public let source: URL
    public let kind: PluginLocalSourceKind
    /// SHA-256 of the archive, for zips.
    public let sha256: String?
    public let warnings: [String]
    /// Folder that holds the copy; remove it with `discard()` once installed or cancelled.
    public let stagingRoot: URL

    public func discard() { try? FileManager.default.removeItem(at: stagingRoot) }
}

/// Plugins added from this Mac instead of the registry (#83): validates them with clear messages and stages a copy.
/// The same checks as registry archives apply (one plugin folder, no links leaving it, a valid manifest and an
/// executable entrypoint), but there is no checksum or signature to verify, so the user's approval is the only trust.
public enum PluginLocalSource {
    public static let archiveExtensions: Set<String> = ["zip", "bashcutplugin"]

    /// The kind of source at `url`, or nil when it is none of them.
    public static func kind(of url: URL) -> PluginLocalSourceKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            // A `.bashcutplugin` bundle folder is just a plugin folder.
            return .folder
        }
        if url.lastPathComponent == "plugin.json" { return .manifest }
        if archiveExtensions.contains(url.pathExtension.lowercased()) { return .archive }
        return nil
    }

    /// Checks `url` without installing anything. Zips are unpacked into a temporary folder that is removed again.
    public static func validate(_ url: URL) -> PluginValidation {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("bashcut-validate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var report = PluginValidation()
        do {
            let (kind, folder, sha256) = try prepare(url, in: temporary, copyFolder: false)
            report.kind = kind
            report.sha256 = sha256
            inspect(folder, into: &report)
        } catch {
            report.problems.append(error.localizedDescription)
        }
        return report
    }

    /// Copies (or unpacks) the plugin into a new folder under `stagingParent` and checks it. Throws every problem
    /// `validate` would report.
    public static func stage(_ url: URL, stagingParent: URL) throws -> StagedLocalPlugin {
        let manager = FileManager.default
        try manager.createDirectory(at: stagingParent, withIntermediateDirectories: true)
        let stagingRoot = stagingParent.appendingPathComponent(".add-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let (kind, folder, sha256) = try prepare(url, in: stagingRoot, copyFolder: true)
            var report = PluginValidation()
            inspect(folder, into: &report)
            guard let manifest = report.manifest, report.problems.isEmpty else {
                throw PluginError.invalid(report.problems.joined(separator: "\n"))
            }
            // Name the folder after the plugin id, as installs are.
            let named = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
            try manager.moveItem(at: folder, to: named)
            try? manager.removeItem(at: stagingRoot.appendingPathComponent("source", isDirectory: true))
            try? PluginArchiveInstaller.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", named.path])
            return StagedLocalPlugin(
                plugin: InstalledPlugin(manifest: manifest, directory: named), source: url.standardizedFileURL,
                kind: kind, sha256: sha256, warnings: report.warnings, stagingRoot: stagingRoot)
        } catch {
            try? manager.removeItem(at: stagingRoot)
            throw error
        }
    }

    /// Finds the plugin folder for `url`: unpacks a zip into `work`, and with `copyFolder` copies a folder there too.
    private static func prepare(
        _ url: URL, in work: URL, copyFolder: Bool
    ) throws -> (PluginLocalSourceKind, URL, String?) {
        guard let kind = kind(of: url) else {
            if !FileManager.default.fileExists(atPath: url.path) { throw PluginError.invalid("Nothing at \(url.path)") }
            throw PluginError.invalid(
                "Choose a plugin folder, its plugin.json, or a .zip or .bashcutplugin archive (\(url.lastPathComponent))")
        }
        let source = work.appendingPathComponent("source", isDirectory: true)
        switch kind {
        case .archive:
            let sha256 = try PluginArchiveInstaller.sha256(of: url)
            return (kind, try PluginArchiveInstaller.unpackSingleFolder(url, into: source), sha256)
        case .folder, .manifest:
            let folder = kind == .manifest ? url.deletingLastPathComponent() : url
            try PluginArchiveInstaller.checkLinks(in: folder)
            guard copyFolder else { return (kind, folder, nil) }
            let manager = FileManager.default
            try manager.createDirectory(at: source, withIntermediateDirectories: true)
            let copy = source.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try manager.copyItem(at: folder, to: copy)
            return (kind, copy, nil)
        }
    }

    /// Reads and checks `folder/plugin.json` and the entrypoint, adding what is wrong to `report`.
    static func inspect(_ folder: URL, into report: inout PluginValidation) {
        let manifestURL = folder.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            report.problems.append("No plugin.json in \(folder.lastPathComponent): a plugin folder needs one at its top level")
            return
        }
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch let error as DecodingError {
            report.problems.append("plugin.json: " + describe(error))
            return
        } catch {
            report.problems.append("plugin.json: \(error.localizedDescription)")
            return
        }
        report.manifest = manifest
        do { try manifest.validate() } catch { report.problems.append("plugin.json: \(error.localizedDescription)") }
        if let incompatibility = manifest.incompatibility { report.problems.append(incompatibility) }
        if let category = manifest.category, PluginCategory(rawValue: category) == nil {
            report.warnings.append(
                "Unknown category \"\(category)\"; it is shown under Utilities. Use one of "
                    + PluginCategory.allCases.map(\.rawValue).joined(separator: ", "))
        }
        // `validate` already refused a path that leaves the folder; here, check the file itself.
        let entrypoint = folder.appendingPathComponent(manifest.entrypoint).standardizedFileURL
        if manifest.entrypoint.isEmpty || !entrypoint.path.hasPrefix(folder.standardizedFileURL.path + "/") {
            return
        }
        if !FileManager.default.fileExists(atPath: entrypoint.path) {
            report.problems.append("entrypoint \(manifest.entrypoint) does not exist")
        } else if !FileManager.default.isExecutableFile(atPath: entrypoint.path) {
            report.problems.append("entrypoint \(manifest.entrypoint) is not executable (chmod +x \(manifest.entrypoint))")
        }
    }

    /// A decoding error as the field it is about and what was expected.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context, _ key: CodingKey? = nil) -> String {
            let keys = context.codingPath + (key.map { [$0] } ?? [])
            return keys.map { $0.intValue.map { "[\($0)]" } ?? "." + $0.stringValue }.joined()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "\"\(path(context, key))\" is required"
        case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
            return "\"\(path(context))\" must be \(typeName(type))"
        case .dataCorrupted(let context):
            let field = path(context)
            if field.isEmpty { return "not valid JSON (\(context.debugDescription))" }
            return "\"\(field)\": \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Int.Type: "an integer"
        case is Double.Type: "a number"
        case is Bool.Type: "true or false"
        case is [Any].Type: "an array"
        default: String(describing: type).hasPrefix("Array") ? "an array" : "an object"
        }
    }
}
