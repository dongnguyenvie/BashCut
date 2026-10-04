import Foundation

/// Settings for a new document; subsequent project changes go through EditOperation.
public struct ProjectSetup: Sendable {
    public enum Canvas: String, CaseIterable, Sendable {
        case portrait, landscape, square
    }
    public enum Resolution: Int, CaseIterable, Sendable {
        case hd = 720, fullHD = 1080, ultraHD = 2160
    }
    public enum Rate: String, CaseIterable, Sendable {
        case ntsc = "29.97", thirty = "30", twentyFour = "24", sixty = "60"
        public var fps: FrameRate {
            self == .ntsc ? FrameRate(30000, 1001) : FrameRate(Int(rawValue) ?? 30, 1)
        }
    }

    public var name = ""
    public var canvas: Canvas = .portrait
    /// The first picture clip sets the canvas shape (`canvasFromFirstClip`); `canvas` holds until then.
    public var canvasFromFirstClip = true
    public var resolution: Resolution = .fullHD
    public var rate: Rate = .ntsc
    public var contentLanguage = "vi"

    public init() {}

    public var folderName: String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
        return folded.components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
    }

    public var dimensions: (width: Int, height: Int) { canvas.dimensions(shortSide: resolution.rawValue) }

    public func project() throws -> Project {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120, !folderName.isEmpty, folderName.utf8.count <= 120 else {
            throw ProjectError.invalid("Use a project name with letters or numbers, up to 120 characters.")
        }
        let language = contentLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard language.count <= 64,
            language.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil
        else { throw ProjectError.invalid("Use a language tag such as vi, en or en-US.") }
        var project = Project(name: title, fps: rate.fps, contentLanguage: language)
        var format = project["format"]?.object ?? [:]
        format["width"] = .integer(dimensions.width)
        format["height"] = .integer(dimensions.height)
        project["format"] = .object(format)
        // New projects show the whole picture: footage of another shape gets bars instead of being cropped.
        project["clipFill"] = .bool(false)
        if canvasFromFirstClip { project["canvasFromFirstClip"] = .bool(true) }
        try project.validate()
        return project
    }
}
