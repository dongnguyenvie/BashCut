import BashCutProject

extension CommandCatalog {
    /// Adjustment items and style kits, mirroring the Filters library.
    static let styleSpecs: [CommandSpec] = [
        CommandSpec(
            "adjustment.add", .edit,
            "Add an adjustment item: a color grade (look, exposure/contrast/saturation, LUT) applied to every layer "
                + "below it for its frame range. Defaults to the selected clip's range, else 3 seconds at the playhead; "
                + "goes on the first adjustment layer, adding one above the video layers when needed.",
            parameters: [
                CommandParameter("look", .string, "Color look", default: .string("original"),
                                 choices: ColorLook.all.map(\.id), cli: .option("look")),
                CommandParameter("lut", .string, "LUT ID from project.get luts", cli: .option("lut")),
                CommandParameter("atFrame", .integer, "First timeline frame", minimum: 0, cli: .option("at-frame")),
                CommandParameter("duration", .integer, "Length in timeline frames", minimum: 1, cli: .option("duration")),
                CommandParameter("track", .string, "Adjustment layer ID", cli: .option("track")),
                baseRevision,
            ]),
        CommandSpec(
            "style.apply", .edit,
            "Apply a style kit as one undoable edit: a full-length adjustment item with the kit's look (replacing one "
                + "an earlier kit added) and the kit's preset on every caption (titles and cards keep theirs). food-review: vivid + Bold Outline; "
                + "cinematic: muted film + Cinematic Serif. Apply after captions exist; afterwards everything stays "
                + "editable on its own.",
            parameters: [
                CommandParameter("kit", .string, "Style kit", required: true, choices: StyleKit.all.map(\.id),
                                 cli: .positional),
                baseRevision,
            ]),
    ]
}
