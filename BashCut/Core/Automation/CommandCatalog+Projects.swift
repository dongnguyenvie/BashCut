import BashCutProject

extension CommandCatalog {
    /// Opening, creating and saving projects, and the default projects folder.
    static let projectSpecs: [CommandSpec] = [
        CommandSpec(
            "project.open", .edit,
            "Open a project.bashcut.json (or its folder). Fails if the open project has unsaved changes "
                + "unless saveCurrent or discardCurrent is set. Agent tabs stay open; every agent must read the new "
                + "project (context get or timeline get) before its next edit.",
            parameters: [
                CommandParameter("path", .string, "Absolute path to project.bashcut.json or its folder", required: true,
                                 isPath: true, cli: .positional)
            ] + leaveCurrent),
        CommandSpec(
            "project.create", .edit,
            "Create a project folder (media, footage, render…) like the New Project wizard and open it.",
            parameters: [
                CommandParameter("name", .string, "Project name", required: true, cli: .option("name")),
                CommandParameter("directory", .string,
                                 "Absolute parent folder for the new project folder; defaults to the projects folder "
                                     + "(see project folder)",
                                 isPath: true, cli: .option("dir")),
                CommandParameter("footage", .string, "Footage folder to link (never modified)", isPath: true,
                                 cli: .option("footage")),
                CommandParameter("canvas", .string,
                                 "Canvas; auto starts portrait and lets the first video or image clip set the shape",
                                 default: .string("auto"), choices: ["auto", "portrait", "landscape", "square"],
                                 cli: .option("canvas")),
                CommandParameter("resolution", .string, "Short-side resolution", default: .string("1080"),
                                 choices: ["720", "1080", "2160"], cli: .option("resolution")),
                CommandParameter("fps", .string, "Frame rate", default: .string("29.97"),
                                 choices: ["29.97", "30", "24", "60"], cli: .option("fps")),
                CommandParameter("language", .string, "Content language tag", default: .string("vi"),
                                 cli: .option("language")),
            ] + leaveCurrent),
        CommandSpec(
            "project.folder", .edit,
            "Show the projects folder that New Project and project create use by default (Settings › General), or "
                + "change it: a path sets it, --reset returns to ~/Movies/BashCut.",
            parameters: [
                CommandParameter("path", .string, "Absolute path of an existing folder", isPath: true, cli: .positional),
                CommandParameter("reset", .boolean, "Use ~/Movies/BashCut again", default: .bool(false),
                                 cli: .flag("reset")),
            ]),
        CommandSpec("project.save", .edit, "Save the open project to disk."),
    ]
}
