import Foundation

/// A clip item (P2-H5): footage kept in the library, such as a generated or downloaded B-roll shot or still. Its
/// file is a movie or an image; placing it copies the file into the project's `clips` folder (once per content),
/// imports it and places it like `media place`. Params are free: `seconds`, `width`, `height` and `hasAudio` record
/// what `library add` measured, and a provider's own keys (model, prompt, aspect…) round-trip.
public enum LibraryClip {
    /// The project folder placed clips are copied into.
    public static let projectFolder = "clips"
    public static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    public static var imageExtensions: Set<String> { LibrarySticker.imageExtensions }

    /// Checks that `file` is a movie or an image; `label` starts the error message.
    public static func validate(file: String?, label: String) throws {
        guard let file else { throw ProjectError.invalid("\(label): a clip needs a file") }
        let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
        guard videoExtensions.contains(ext) || imageExtensions.contains(ext) else {
            throw ProjectError.invalid("\(label): a clip file must be a movie (.mov, .mp4, .m4v) or an image")
        }
    }

    /// Whether the file is placed as an image rather than a movie.
    public static func isImage(_ file: String) -> Bool {
        imageExtensions.contains(URL(fileURLWithPath: file).pathExtension.lowercased())
    }
}
