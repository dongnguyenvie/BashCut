import BashCutProject

extension CommandCatalog {
    /// The Stickers panel: the user's image library and the sticker packs of plugins.
    static let stickerSpecs: [CommandSpec] = [
        CommandSpec(
            "stickers.list", .read,
            "List image stickers: the library shared by every project (My stickers) and each plugin sticker pack, "
                + "with the path to give stickers.add."),
        CommandSpec(
            "stickers.add", .edit,
            "Place an image sticker like a click in the Stickers panel: copied into the project's stickers folder (an "
                + "animated GIF, APNG or WebP becomes a movie with alpha) and put on a free overlay layer at 35 % zoom.",
            parameters: [
                CommandParameter("path", .string, "Image path, from stickers.list or any image file", required: true,
                                 isPath: true, cli: .positional),
                CommandParameter("atFrame", .integer, "Timeline frame; defaults to the playhead", minimum: 0,
                                 cli: .option("at-frame")),
                baseRevision,
            ]),
        CommandSpec(
            "stickers.import", .edit,
            "Copy an image file into the sticker library (My stickers); a name already there is kept as it is.",
            parameters: [
                CommandParameter("path", .string, "Image file path", required: true, isPath: true, cli: .positional)
            ]),
        CommandSpec(
            "stickers.remove", .edit,
            "Remove a sticker from the library by file name; projects that used it keep their own copy.",
            parameters: [
                CommandParameter("name", .string, "File name in the library, from stickers.list", required: true, cli: .positional)
            ]),
    ]
}
