import BashCutProject

extension CommandCatalog {
    /// The canvas of the open project (the toolbar's format menu).
    static let formatSpecs: [CommandSpec] = [
        CommandSpec(
            "project.format", .edit,
            "Change the open project's canvas like the format menu in the toolbar: portrait 9:16, landscape 16:9 or "
                + "square, at a short-side resolution (the current one by default). One undoable edit; timing is kept "
                + "and clip pan/tilt scale with the frame.",
            parameters: [
                CommandParameter("canvas", .string, "Canvas", required: true,
                                 choices: ["portrait", "landscape", "square"], cli: .option("canvas")),
                CommandParameter("resolution", .string, "Short-side resolution; the current one by default",
                                 choices: ["720", "1080", "2160"], cli: .option("resolution")),
                baseRevision,
            ]),
    ]
}
