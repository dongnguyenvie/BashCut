import BashCutProject
import Foundation

/// Generated illustrations (#550): an `image.generate` provider makes every scene in one job, the style lock keeps one
/// look and character, and disclosure labels go over generated pictures. Mascot poses from a photo or from one
/// reference (#551).
extension CommandCatalog {
    static let imageSpecs: [CommandSpec] = [
        CommandSpec(
            "image.generate", .edit,
            "Make pictures with an image.generate provider: every scene in one job (the batch form: a JSON file of "
                + "[{id, prompt}] or of prompt texts), with the style lock (image style: style prompt, reference "
                + "pictures, seed) sent each time and the project's frame size. Each picture is added to the media "
                + "pool with generated: true and its prompt, so media place puts it on the timeline. Returns images "
                + "[{id, media, path, projectPath, width, height}], failed [{id, message}] (only those scenes need "
                + "another call), contactSheet (one PNG of every picture, labelled by id: look at it instead of each "
                + "picture), the style used and the provider. A job.",
            parameters: [
                CommandParameter("prompts", .array, "Scenes [{id, prompt}] or prompt texts (CLI: path to a JSON file)",
                                 sensitive: true, cli: .positionalJSONFile),
                CommandParameter("prompt", .string, "One picture's prompt, instead of prompts", sensitive: true,
                                 cli: .option("prompt")),
                CommandParameter("style", .string, "Style prompt for this call instead of the style lock's",
                                 cli: .option("style")),
                CommandParameter("references", .string, "Comma-separated reference pictures (paths or sticker library "
                                 + "ids) for this call instead of the style lock's", cli: .option("references")),
                CommandParameter("seed", .integer, "Seed for this call instead of the style lock's", minimum: 0,
                                 cli: .option("seed")),
                CommandParameter("noLock", .boolean, "Ignore the style lock for this call", default: .bool(false),
                                 cli: .flag("no-lock")),
                CommandParameter("width", .integer, "Picture width; the project's by default", minimum: 64,
                                 maximum: 8_192, cli: .option("width")),
                CommandParameter("height", .integer, "Picture height; the project's by default", minimum: 64,
                                 maximum: 8_192, cli: .option("height")),
                provider,
            ], execution: .job),
        CommandSpec(
            "image.generate-list", .read,
            "The project's generated pictures (media with generated: true): per picture media, id, prompt, "
                + "projectPath, provider and placed (timeline items using it); the style lock in use with where it "
                + "comes from (project or brand); the disclosure label; and whether an image.generate provider is "
                + "available (with what to install when not)."),
        CommandSpec(
            "image.style", .edit,
            "Read or set the project's style lock for image generate: style prompt, reference pictures (paths or "
                + "sticker library ids), seed and the disclosure label shown over generated pictures. Given fields "
                + "replace those fields; clear removes the project's lock (a brand kit's illustration then applies). "
                + "With no field, returns the lock in use.",
            parameters: [
                CommandParameter("style", .string, "Style prompt", cli: .option("style")),
                CommandParameter("references", .string, "Comma-separated reference pictures; empty clears them",
                                 cli: .option("references")),
                CommandParameter("seed", .integer, "Seed, for providers that take one", minimum: 0, cli: .option("seed")),
                CommandParameter("disclosure", .string, "Label over generated pictures, such as the brand's",
                                 cli: .option("disclosure")),
                CommandParameter("clear", .boolean, "Remove the project's lock", default: .bool(false), cli: .flag("clear")),
            ]),
        CommandSpec(
            "image.disclose", .edit,
            "Put the disclosure label over every generated picture on the timeline that lacks one: one text item "
                + "(disclosure: true, small, top left) per run of generated pictures, on the titles layer, in one undo "
                + "step. The label is text, else the style lock's or the brand's disclosure. Returns rev and the added "
                + "items; move or restyle them like any text. Only when the user asks: by default nothing generated "
                + "is labelled on the video (AI disclosure is the platform's upload toggle).",
            parameters: [
                CommandParameter("text", .string, "Label text for this call", cli: .option("text")),
            ]),
        CommandSpec(
            "library.brand-pose", .edit,
            "Add a mascot pose to a brand kit (#551). With image: the photo's subject is cut out with a vision.cutout "
                + "provider, saved as a sticker and stored as the pose. With generate: every pose name not in the kit "
                + "yet is made with an image.generate provider from one reference (an existing pose, or reference), "
                + "cut out and stored, in one job. Returns poses [{pose, sticker}], failed and the kit. A job.",
            parameters: [
                CommandParameter("brand", .string, "Brand kit library id", required: true, cli: .positional),
                CommandParameter("pose", .string, "Pose name (with image), or comma-separated pose names (with generate)",
                                 required: true, cli: .option("pose")),
                CommandParameter("image", .string, "Photo or picture to cut the pose from (relative to the project or "
                                 + "absolute), or a sticker library id", cli: .option("image")),
                CommandParameter("generate", .boolean, "Generate the poses not in the kit yet", default: .bool(false),
                                 cli: .flag("generate")),
                CommandParameter("reference", .string, "With generate: the picture or sticker id of the character; the "
                                 + "kit's first pose by default", cli: .option("reference")),
                CommandParameter("scope", .string, "Library scope the pose stickers go into; the kit's by default",
                                 choices: ["project", "user"], cli: .option("scope")),
                provider,
            ], execution: .job),
    ]
}
