import BashCutProject

extension CommandCatalog {
    /// Color grade options of `adjustment add`, generated from `ColorGrade`.
    private static let gradeParameters: [CommandParameter] =
        ColorGrade.ranges.map { key, range in
            CommandParameter(
                key, .number, ColorGrade.summaries[key] ?? key, range: range,
                cli: .option(key.replacingOccurrences(of: "lutStrength", with: "lut-strength")))
        } + [CommandParameter("lut", .string, "LUT ID from timeline get luts", cli: .option("lut"))]

    private static let builtInLooks = LibraryBuiltIns.looks.map(\.id).joined(separator: ", ")

    /// Adjustment items. Looks are library `look` items (`library list --kind look`, `library place`, `library add`).
    static let styleSpecs: [CommandSpec] = [
        CommandSpec(
            "adjustment.add", .edit,
            "Add an adjustment item: a color grade applied to every layer below it for its frame range. Starts from "
                + "a library look without a file, then the given grade values and LUT override it. Defaults to the selected clip's range, "
                + "else 3 seconds at the playhead; goes on the first adjustment layer, adding one when needed.",
            parameters: [
                CommandParameter(
                    "look", .string, "Library look: built-in (\(builtInLooks)) or scope:id from library list --kind look",
                    default: .string("original"), cli: .option("look")),
            ] + gradeParameters + [
                CommandParameter("atFrame", .integer, "First timeline frame", minimum: 0, cli: .option("at-frame")),
                CommandParameter("duration", .integer, "Length in timeline frames", minimum: 1, cli: .option("duration")),
                CommandParameter("track", .string, "Adjustment layer ID", cli: .option("track")),
                baseRevision,
            ]),
        CommandSpec(
            "schema.get", .read,
            "Read the project.bashcut.json JSON Schema: every field, its type and range. Generated from the same "
                + "declarations the app validates with."),
    ]
}
