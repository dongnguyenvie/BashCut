import BashCutProject

extension CommandCatalog {
    /// Color grade options shared by `adjustment add` and `looks save`, generated from `ColorGrade`.
    private static let gradeParameters: [CommandParameter] =
        ColorGrade.ranges.map { key, range in
            CommandParameter(
                key, .number, ColorGrade.summaries[key] ?? key, range: range,
                cli: .option(key.replacingOccurrences(of: "lutStrength", with: "lut-strength")))
        } + [CommandParameter("lut", .string, "LUT ID from timeline get luts", cli: .option("lut"))]

    private static let builtInLooks = ColorLook.builtIn.map(\.id).joined(separator: ", ")
    private static let builtInKits = StyleKit.builtIn.map(\.id).joined(separator: ", ")

    /// Adjustment items, looks and style kits, mirroring the Filters library.
    static let styleSpecs: [CommandSpec] = [
        CommandSpec(
            "adjustment.add", .edit,
            "Add an adjustment item: a color grade applied to every layer below it for its frame range. Starts from "
                + "a look, then the given grade values and LUT override it. Defaults to the selected clip's range, "
                + "else 3 seconds at the playhead; goes on the first adjustment layer, adding one when needed.",
            parameters: [
                CommandParameter(
                    "look", .string, "Look ID: built-in (\(builtInLooks)) or custom from timeline get looks",
                    default: .string("original"), cli: .option("look")),
            ] + gradeParameters + [
                CommandParameter("atFrame", .integer, "First timeline frame", minimum: 0, cli: .option("at-frame")),
                CommandParameter("duration", .integer, "Length in timeline frames", minimum: 1, cli: .option("duration")),
                CommandParameter("track", .string, "Adjustment layer ID", cli: .option("track")),
                baseRevision,
            ]),
        CommandSpec(
            "style.apply", .edit,
            "Apply a style kit as one undoable edit: a full-length adjustment item with the kit's look (replacing one "
                + "an earlier kit added) and the kit's preset on captions (titles and cards keep theirs). Apply after "
                + "captions exist; afterwards everything stays editable on its own.",
            parameters: [
                CommandParameter(
                    "kit", .string, "Kit ID: built-in (\(builtInKits)) or custom from timeline get styleKits",
                    required: true, cli: .positional),
                baseRevision,
            ]),
        CommandSpec(
            "looks.save", .edit,
            "Save a custom look in the project (it appears in Filters › Looks and works with adjustment add). Starts "
                + "from an item's grade when item is given, then the grade values override it. Saving an existing "
                + "custom ID replaces it; built-in IDs are reserved.",
            parameters: [
                CommandParameter("id", .string, "Look ID: lowercase letters, digits and hyphens", required: true,
                                 cli: .positional),
                CommandParameter("title", .string, "Display name", required: true, cli: .option("title")),
                CommandParameter("item", .string, "Copy the color of this item first", cli: .option("item")),
            ] + gradeParameters + [baseRevision]),
        CommandSpec(
            "looks.delete", .edit, "Delete a custom look; refused while a custom style kit uses it.",
            parameters: [
                CommandParameter("id", .string, "Custom look ID", required: true, cli: .positional), baseRevision,
            ]),
        CommandSpec(
            "style.save", .edit,
            "Save a custom style kit in the project (it appears in Filters › Style kits and works with style apply). "
                + "Saving an existing custom ID replaces it; built-in IDs are reserved.",
            parameters: [
                CommandParameter("id", .string, "Kit ID: lowercase letters, digits and hyphens", required: true,
                                 cli: .positional),
                CommandParameter("title", .string, "Display name", required: true, cli: .option("title")),
                CommandParameter("look", .string, "Built-in or custom look ID", required: true, cli: .option("look")),
                CommandParameter(
                    "captionPreset", .string, "Text preset given to captions", default: .string("bold-outline"),
                    choices: TextPreset.all, cli: .option("caption-preset")),
                baseRevision,
            ]),
        CommandSpec(
            "style.delete", .edit, "Delete a custom style kit.",
            parameters: [
                CommandParameter("id", .string, "Custom kit ID", required: true, cli: .positional), baseRevision,
            ]),
        CommandSpec(
            "schema.get", .read,
            "Read the project.bashcut.json JSON Schema: every field, its type and range. Generated from the same "
                + "declarations the app validates with."),
    ]
}
