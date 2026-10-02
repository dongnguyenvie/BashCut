import AppKit
import BashCutAutomation
import BashCutProject
import Foundation
import Observation

/// One choice in a dialog. `id` is stable English for agents; `title` is what the user sees.
public struct ModalOption: Sendable, Equatable {
    public let id: String
    public let title: String
    public init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

/// A dialog as automation sees it.
public struct ModalSnapshot: Sendable, Equatable {
    public enum Kind: String, Sendable { case alert, open, save, sheet }

    public let id: String
    public let kind: Kind
    /// Stable dialog name, e.g. `discard-changes`, `import-media`, `export`.
    public let name: String
    public let title: String
    public let message: String?
    public let options: [ModalOption]
    /// Open and save panels are answered with a `path` (or `cancel`).
    public var acceptsPath: Bool { kind == .open || kind == .save }

    public init(
        id: String = UUID().uuidString, kind: Kind, name: String, title: String, message: String? = nil,
        options: [ModalOption]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.title = title
        self.message = message
        self.options = options
    }

    public var json: JSONValue {
        .object([
            "id": .string(id), "kind": .string(kind.rawValue), "name": .string(name), "title": .string(title),
            "message": message.map(JSONValue.string) ?? .null,
            "options": .array(options.map { .object(["id": .string($0.id), "title": .string($0.title)]) }),
            "acceptsPath": .bool(acceptsPath),
        ])
    }
}

/// A SwiftUI sheet or popover that is open, with what choosing an option does.
public struct ModalSheet {
    public let snapshot: ModalSnapshot
    public let respond: @MainActor (String) throws -> Void
    public init(
        name: String, title: String, message: String? = nil, options: [ModalOption],
        respond: @escaping @MainActor (String) throws -> Void
    ) {
        snapshot = ModalSnapshot(id: "sheet:" + name, kind: .sheet, name: name, title: title, message: message,
                                 options: options)
        self.respond = respond
    }
}

/// Every dialog in the app goes through here so agents can read and answer it (`ui.dialog`,
/// `ui.respond`) exactly like the user: alerts and file panels run through `alert`/`open`/`save`,
/// and SwiftUI sheets are reported by `sheets`.
@MainActor @Observable
public final class ModalCenter {
    public static let shared = ModalCenter()

    private struct Entry {
        let snapshot: ModalSnapshot
        let respond: @MainActor (_ option: String?, _ path: URL?) throws -> Void
    }

    private var entries: [Entry] = []
    /// Open sheets and popovers, topmost last; set by the app.
    @ObservationIgnored public var sheets: @MainActor () -> [ModalSheet] = { [] }
    @ObservationIgnored private var injectedPaths: [ObjectIdentifier: [URL]] = [:]

    public init() {}

    /// All open dialogs, topmost last. AppKit modals sit above sheets.
    public var open: [ModalSnapshot] { sheets().map(\.snapshot) + entries.map(\.snapshot) }
    public var current: ModalSnapshot? { open.last }

    /// Answers the topmost dialog (or `dialog`, when given) with an option ID or title, or a path.
    public func respond(option: String?, path: URL?, dialog: String? = nil) throws {
        if let dialog, current?.id != dialog {
            guard open.contains(where: { $0.id == dialog }) else { throw ModalError("No open dialog \(dialog)") }
            throw ModalError("Dialog \(dialog) is behind another dialog; answer \(current?.id ?? "") first")
        }
        if let entry = entries.last {
            try entry.respond(try option.map { try Self.match($0, in: entry.snapshot) }, path)
            return
        }
        guard let sheet = sheets().last else { throw ModalError("No dialog is open") }
        guard let option else { throw ModalError("Choose one of: \(Self.list(sheet.snapshot))") }
        try sheet.respond(try Self.match(option, in: sheet.snapshot))
    }

    // MARK: AppKit modals

    /// Runs an alert and returns the chosen button's ID (the first button is the default).
    public func alert(
        _ name: String, title: String, message: String? = nil, buttons: [ModalOption],
        style: NSAlert.Style = .warning
    ) -> String {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        if let message { alert.informativeText = message }
        for button in buttons { alert.addButton(withTitle: button.title) }
        let snapshot = ModalSnapshot(kind: .alert, name: name, title: title, message: message, options: buttons)
        let index = run(snapshot) { option, _ in
            guard let option, let index = buttons.firstIndex(where: { $0.id == option }) else {
                throw ModalError("Choose one of: \(Self.list(snapshot))")
            }
            alert.buttons[index].performClick(nil)
        } modal: {
            alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        }
        return buttons.indices.contains(index) ? buttons[index].id : buttons.last?.id ?? ""
    }

    /// Runs an open panel; nil when cancelled. Automation may answer with a `path`.
    public func open(_ panel: NSOpenPanel, name: String) -> [URL]? {
        runPanel(panel, kind: .open, name: name)
    }

    /// Runs a save panel; nil when cancelled. Automation may answer with a `path`.
    public func save(_ panel: NSSavePanel, name: String) -> URL? {
        runPanel(panel, kind: .save, name: name)?.first
    }

    private func runPanel(_ panel: NSSavePanel, kind: ModalSnapshot.Kind, name: String) -> [URL]? {
        let title = [panel.message, panel.title].first { !$0.isEmpty } ?? name
        let snapshot = ModalSnapshot(
            kind: kind, name: name, title: title,
            options: [ModalOption("cancel", String(localized: "Cancel"))])
        let key = ObjectIdentifier(panel)
        defer { injectedPaths[key] = nil }
        let response = run(snapshot) { [weak self] option, path in
            if let path {
                try Self.validate(path, for: panel)
                self?.injectedPaths[key] = [path]
                panel.cancel(nil)
            } else if option == "cancel" {
                panel.cancel(nil)
            } else {
                // Never call `panel.ok`: confirming the remote panel programmatically can break the
                // open/save panel service and stall the main actor.
                throw ModalError("Answer with --path <file>, or choose cancel")
            }
        } modal: {
            panel.runModal()
        }
        if let injected = injectedPaths[key] { return injected }
        guard response == .OK else { return nil }
        return (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
    }

    private func run<T>(
        _ snapshot: ModalSnapshot, respond: @escaping @MainActor (String?, URL?) throws -> Void,
        modal: () -> T
    ) -> T {
        entries.append(Entry(snapshot: snapshot, respond: respond))
        DebugLog.write("ui", "dialog \(snapshot.kind.rawValue) \(snapshot.name) opened")
        defer {
            entries.removeAll { $0.snapshot.id == snapshot.id }
            DebugLog.write("ui", "dialog \(snapshot.name) closed")
        }
        return modal()
    }

    private static func validate(_ path: URL, for panel: NSSavePanel) throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
        guard let open = panel as? NSOpenPanel else {
            guard FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path) else {
                throw ModalError("The folder of \(path.path) does not exist")
            }
            return
        }
        guard exists else { throw ModalError("\(path.path) does not exist") }
        if isDirectory.boolValue, !open.canChooseDirectories, !open.treatsFilePackagesAsDirectories,
            path.pathExtension.isEmpty
        {
            throw ModalError("This dialog needs a file, not a folder")
        }
        if !isDirectory.boolValue, !open.canChooseFiles { throw ModalError("This dialog needs a folder") }
    }

    private static func match(_ option: String, in snapshot: ModalSnapshot) throws -> String {
        let wanted = option.trimmingCharacters(in: .whitespaces).lowercased()
        if let found = snapshot.options.first(where: { $0.id.lowercased() == wanted || $0.title.lowercased() == wanted }) {
            return found.id
        }
        throw ModalError("Unknown option \(option); choose one of: \(list(snapshot))")
    }

    private static func list(_ snapshot: ModalSnapshot) -> String {
        snapshot.options.map(\.id).joined(separator: ", ")
    }
}

public struct ModalError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
