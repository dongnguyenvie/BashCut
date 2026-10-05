import BashCutProject

extension CommandCatalog {
    private static let pluginID = CommandParameter("plugin", .string, "Plugin ID", required: true, cli: .positional)
    static let pluginCategory = CommandParameter(
        "category", .string, "Only plugins in this category", choices: UIAction.pluginCategories,
        cli: .option("category"))

    /// Plugin contributions (actions, hooks, options) and the per-plugin switches, mirroring the Plugins sheet,
    /// the Plugins menu and every place a plugin action appears.
    static let pluginSpecs: [CommandSpec] = [
        CommandSpec(
            "plugins.actions", .read,
            "List actions plugins add to the editor (Plugins menu, toolbar, context menus, panels) with their "
                + "parameters as JSON Schema, placements and whether each is available now."),
        CommandSpec(
            "plugins.run", .edit,
            "Run a plugin action like clicking it, with parameters (CLI: --params '{\"mode\":\"vivid\"}'). The plugin's "
                + "proposed operations are validated and applied as one undoable edit attributed to the plugin.",
            parameters: [
                CommandParameter("action", .string, "Action ID from plugins actions", required: true, cli: .positional),
                CommandParameter("params", .object, "Action parameters (JSON object)", sensitive: true, cli: .option("params")),
            ],
            execution: .job),
        CommandSpec(
            "plugins.hooks", .read,
            "List plugin hook subscriptions, the recent hook runs and hook edits waiting for review."),
        CommandSpec(
            "plugins.proposal", .edit,
            "Apply or discard an edit a plugin hook proposed (Settings decides whether hook edits wait for review).",
            parameters: [
                CommandParameter("id", .string, "Proposal ID from plugins hooks", required: true, cli: .positional),
                CommandParameter("decision", .string, "What to do", required: true, choices: ["apply", "discard"],
                                 cli: .option("decision")),
            ]),
        CommandSpec(
            "plugins.options", .read, "Read a plugin's options (schema, scope and current values).",
            parameters: [pluginID]),
        CommandSpec(
            "plugins.option", .edit,
            "Set one plugin option like the Plugins sheet: project-scope values are an undoable project edit, "
                + "user-scope values are saved for this Mac. Omit value to reset it to the default.",
            parameters: [
                pluginID,
                CommandParameter("option", .string, "Option ID", required: true, cli: .option("option")),
                CommandParameter("value", .string, "New value as text (on/off, numbers, choices)", sensitive: true, cli: .option("value")),
            ]),
        CommandSpec(
            "plugins.search", .read,
            "Search the plugin registry (Plugins › Browse): name, summary, category, capability, the version this BashCut would "
                + "install and whether it is installed, has an update or is incompatible.",
            parameters: [
                CommandParameter("query", .string, "Search text", cli: .positional),
                CommandParameter("capability", .string, "Only providers of this capability, such as captions.transcribe",
                                 cli: .option("capability")),
                pluginCategory,
                CommandParameter("refresh", .boolean, "Fetch the registry again instead of using the 5-minute cache",
                                 default: .bool(false), cli: .flag("refresh")),
            ]),
        CommandSpec("plugins.updates", .read, "List installed plugins with a newer compatible version in the registry."),
        CommandSpec(
            "plugins.install", .edit,
            "Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in "
                + "the Plugins sheet. Only the user can approve; the job ends when the approval is shown.",
            parameters: [
                CommandParameter("plugin", .string, "Plugin ID from plugins search", required: true, cli: .positional),
                CommandParameter("version", .string, "A specific registry version; the newest compatible by default",
                                 cli: .option("version")),
            ],
            execution: .job),
        CommandSpec(
            "plugins.remove", .edit, "Uninstall a plugin from the user or project plugin folder, with its trust and options (plugins that come with "
                + "BashCut can only be turned off). With data, also delete its downloaded environments and models.",
            parameters: [
                pluginID,
                CommandParameter("data", .boolean, "Also delete the plugin's data and cache folders", default: .bool(false),
                                 cli: .flag("data")),
            ]),
        CommandSpec(
            "plugins.setup", .edit,
            "Show the approval to run an installed plugin's dependency install recipes again (Install Dependencies…). "
                + "Only the user can approve; follow it with jobs status.",
            parameters: [pluginID]),
        CommandSpec(
            "plugins.set", .edit,
            "Turn a plugin or its hooks off (agents can only turn them off; turning on and trusting a plugin stays "
                + "with the user in the Plugins sheet).",
            parameters: [
                pluginID,
                CommandParameter("enabled", .boolean, "Plugin on or off", cli: .option("enabled")),
                CommandParameter("hooks", .boolean, "Hooks on or off", cli: .option("hooks")),
            ]),
    ]
}
