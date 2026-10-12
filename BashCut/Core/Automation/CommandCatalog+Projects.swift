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
            "project.close", .edit,
            "Close the open project and show the Welcome screen, like File › Close Project. Fails if it has unsaved "
                + "changes unless saveCurrent or discardCurrent is set. Agent tabs stay open; edits fail until a "
                + "project is opened or created.",
            parameters: leaveCurrent),
        CommandSpec(
            "project.create", .edit,
            "Create a project folder (media, footage, render…) like the New Project wizard and open it. With "
                + "import, also import every video, audio and image file in footage (as media import FOLDER) and start "
                + "media transcribe and media analyze for them: the result adds import (files, converting) and jobs "
                + "{transcribe, analyze} (a job ID, or {error} when it could not start), so one call readies the "
                + "footage for a survey. A folder of that name without a project (say one the footage was copied "
                + "into) becomes the project: the project folders are added and its files stay where they are.",
            parameters: [
                CommandParameter("name", .string, "Project name", required: true, cli: .option("name")),
                CommandParameter("directory", .string,
                                 "Absolute parent folder for the new project folder; defaults to the projects folder "
                                     + "(see project folder)",
                                 isPath: true, cli: .option("dir")),
                CommandParameter("footage", .string, "Footage folder to link (never modified), or one file: its folder is "
                                 + "linked and import takes only that file", isPath: true,
                                 cli: .option("footage")),
                CommandParameter("canvas", .string,
                                 "Canvas; auto starts portrait and lets the first video or image clip set the shape",
                                 default: .string("auto"), choices: ["auto", "portrait", "landscape", "square"],
                                 cli: .option("canvas")),
                CommandParameter("resolution", .string, "Short-side resolution", default: .string("1080"),
                                 choices: ["720", "1080", "2160"], cli: .option("resolution")),
                CommandParameter("fps", .string, "Frame rate", default: .string("29.97"),
                                 choices: ["29.97", "30", "24", "60"], cli: .option("fps")),
                CommandParameter("language", .string,
                                 "Content language (BCP 47) of speech and captions, from the user's prompt or answer; "
                                     + "no default", cli: .option("language")),
                CommandParameter("importFootage", .boolean,
                                 "Import the footage folder's files and start transcription and picture analysis",
                                 default: .bool(false), cli: .flag("import")),
                CommandParameter("brand", .string,
                                 "A brand kit from the library (this Mac, a plugin or built in) to apply to the new "
                                     + "project, as library apply", cli: .option("brand")),
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
