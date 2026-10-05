import BashCutProject

extension CommandCatalog {
    private static let pluginID = CommandParameter("plugin", .string, "Plugin ID", required: true, cli: .positional)
    private static let pluginURL = CommandParameter(
        "url", .string, "Link to a .zip / .bashcutplugin file, a GitHub repo (or /tree/<ref>/<folder>, or its plugin.json) or a "
            + "GitHub release; #sha256=<hex> pins it. A private link uses the access token saved in Add Plugin…",
        cli: .option("url"))
    private static let pluginRef = CommandParameter(
        "ref", .string, "Tag, branch or commit for a GitHub repo link (release tag for a release link)", cli: .option("ref"))
    private static let pluginSHA256 = CommandParameter(
        "sha256", .string, "Expected SHA-256 of the downloaded archive", cli: .option("sha256"))
    static let pluginCategory = CommandParameter(
        "category", .string, "Only plugins in this category", choices: UIAction.pluginCategories,
        cli: .option("category"))

    /// Plugin contributions (actions, hooks, options) and the per-plugin switches, mirroring the Plugins sheet,
    /// the Plugins menu and every place a plugin action appears.
    static let pluginSpecs: [CommandSpec] = [
        CommandSpec(
            "plugins.actions", .read,
            "List actions plugins add to the editor (Plugins menu, toolbar, context menus, panels) with their "
                + "parameters as JSON Schema, placements, whether each is available now and when it last ran. MCP lists at "
                + "most \(PluginActionTools.budget) of them as their own tools; find any other action here and run it with "
                + "plugins run.",
            parameters: [
                CommandParameter("query", .string, "Only actions whose ID, title or plugin contains this text", cli: .positional),
                CommandParameter("plugin", .string, "Only actions of this plugin ID", cli: .option("plugin")),
            ]),
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
            "plugins.validate", .read,
            "Check a plugin that is not in the registry (a folder, its plugin.json, a .zip or .bashcutplugin archive, or a "
                + "link) without installing or running it: its id, version and capabilities, every problem with the field "
                + "and the fix, and for a link the commit or release it resolved to.",
            parameters: [
                CommandParameter("path", .string, "Plugin folder, plugin.json, or .zip / .bashcutplugin file (or use url)",
                                 isPath: true, cli: .positional),
                pluginURL, pluginRef, pluginSHA256,
            ]),
        CommandSpec(
            "plugins.install", .edit,
            "Download a registry plugin (or its update), check its SHA-256 and manifest, and show the install approval in "
                + "the Plugins sheet. With path or url instead, add a plugin that is not in the registry (Add Plugin…): a "
                + "folder, its plugin.json or a .zip / .bashcutplugin file on this Mac, or a link, checked like plugins "
                + "validate. Only the user can approve; the job ends when the approval is shown.",
            parameters: [
                CommandParameter("plugin", .string, "Plugin ID from plugins search (or use path)", cli: .positional),
                CommandParameter("version", .string, "A specific registry version; the newest compatible by default",
                                 cli: .option("version")),
                CommandParameter("path", .string, "Plugin folder, plugin.json, or .zip / .bashcutplugin file on this Mac",
                                 isPath: true, cli: .option("path")),
                pluginURL, pluginRef, pluginSHA256,
                CommandParameter("scope", .string,
                                 "Where a plugin from path or url goes: user (this Mac, every project; the default) or project (the open project)",
                                 choices: ["user", "project"], cli: .option("scope")),
                CommandParameter("link", .boolean,
                                 "Link (developer mode): install a link to the plugin folder at path instead of a copy; "
                                    + "use plugins reload after editing it",
                                 cli: .flag("link")),
            ],
            execution: .job),
        CommandSpec(
            "plugins.replace", .edit,
            "Replace… an installed plugin with a new version from a folder, its plugin.json or a .zip / .bashcutplugin file, in the "
                + "same scope. The new files must have the same plugin ID; only the user can approve, like plugins install.",
            parameters: [
                pluginID,
                CommandParameter("path", .string, "Folder, plugin.json, or .zip / .bashcutplugin file with the new version",
                                 required: true, isPath: true, cli: .option("path")),
            ],
            execution: .job),
        CommandSpec(
            "plugins.reload", .edit,
            "Reload a plugin after editing it (for linked plugins in developer mode): stop its session and check its files "
                + "again. Changed files make it changed until the user chooses Trust; reload never trusts it.",
            parameters: [pluginID]),
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
