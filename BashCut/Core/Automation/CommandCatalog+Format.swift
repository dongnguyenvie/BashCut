import BashCutProject

extension CommandCatalog {
    /// The canvas of the open project (the toolbar's format menu).
    static let formatSpecs: [CommandSpec] = [
        CommandSpec(
            "project.format", .edit,
            "Change the open project's canvas like the format menu in the toolbar: portrait 9:16, landscape 16:9 or "
                + "square, at a short-side resolution (the current one by default); timing is kept and clip pan/tilt "
                + "scale with the frame. --clips fit shows each clip whole (bars where its shape differs), fill covers "
                + "the frame and crops; a clip's own `fill` property overrides it. Each change is one undoable edit.",
            parameters: [
                CommandParameter("canvas", .string, "Canvas", choices: ["portrait", "landscape", "square"],
                                 cli: .option("canvas")),
                CommandParameter("clips", .string, "How clips meet the frame by default", choices: ["fit", "fill"],
                                 cli: .option("clips")),
                CommandParameter("resolution", .string, "Short-side resolution; the current one by default",
                                 choices: ["720", "1080", "2160"], cli: .option("resolution")),
                baseRevision,
            ]),
    ]
}
