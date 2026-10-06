import BashCutProject

extension CommandCatalog {
    /// Fonts for text items (#415): Inspector › Text › Font.
    static let fontSpecs: [CommandSpec] = [
        CommandSpec(
            "fonts.list", .read,
            "List fonts for text items (Inspector › Text › Font): the project's fonts folder first, then the fonts "
                + "installed on this Mac, with PostScript names (textStyle.font) and Vietnamese coverage.",
            parameters: [
                CommandParameter("query", .string, "Only names or families containing this text", cli: .option("query")),
                CommandParameter("project", .boolean, "Only the project's own fonts", default: .bool(false),
                                 cli: .flag("project")),
                CommandParameter("vietnamese", .boolean, "Only fonts with every Vietnamese letter", default: .bool(false),
                                 cli: .flag("vietnamese")),
            ]),
        CommandSpec(
            "fonts.import", .edit,
            "Copy a .ttf, .otf or .ttc font into the project's fonts folder and use it for this project (Inspector › "
                + "Text › Font › Add Font…). The font travels with the project; nothing is installed on the Mac.",
            parameters: [CommandParameter("path", .string, "Font file", required: true, isPath: true, cli: .positional)]),
    ]
}
