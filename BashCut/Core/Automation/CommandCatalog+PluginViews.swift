import BashCutProject

extension CommandCatalog {
    private static let viewPlugin = CommandParameter("plugin", .string, "Plugin ID", required: true, cli: .positional)
    private static let viewID = CommandParameter(
        "view", .string, "View ID from plugins views; the plugin's first view by default", cli: .option("view"))

    /// Plugin panels in the left rail and their declarative views (plugin API 8), and capability calls between
    /// plugins: everything the plugin panel shows or does.
    static let pluginViewSpecs: [CommandSpec] = [
        CommandSpec(
            "plugins.views", .read,
            "List ready plugins that have a panel in the left rail (plugin API 8): its title and icon, its views, its "
                + "tools (actions), skills, required plugins with their state, the capabilities it uses and whether a "
                + "ready plugin provides each, and which panel is open. Also lists the host's plugin features."),
        CommandSpec(
            "plugins.view", .ui,
            "Render a plugin view and return its components as JSON (what the panel draws: text, lists, inputs with "
                + "their current values, buttons by id). With open, also show the plugin's panel in the left rail on "
                + "this view.",
            parameters: [
                viewPlugin, viewID,
                CommandParameter("open", .boolean, "Show the plugin's panel in the left rail", default: .bool(false),
                                 cli: .flag("open")),
            ]),
        CommandSpec(
            "plugins.view-event", .ui,
            "Do what a user does in a plugin view: click a button, change an input, submit a text field, select a "
                + "list row or press a row button. Returns the view's new components.",
            parameters: [
                viewPlugin, viewID,
                CommandParameter("node", .string, "Component id from plugins view", required: true, cli: .option("node")),
                CommandParameter("type", .string, "What happened", default: .string("click"),
                                 choices: PluginViewEventKinds.all, cli: .option("type")),
                CommandParameter("value", .string,
                                 "New value (change), row id (select) or {\"item\",\"action\"} (action); JSON or text",
                                 sensitive: true, cli: .option("value")),
            ]),
        CommandSpec(
            "plugins.invoke", .edit,
            "Run a plugin capability directly with raw parameters and return the provider's raw result, for capabilities "
                + "without their own command (prefer voice speak, captions generate, beats detect … when one exists). "
                + "Files go to the returned outputDirectory. Plugins call this from their views and actions for "
                + "capabilities listed in their manifest's uses.",
            parameters: [
                CommandParameter("capability", .string, "Capability ID, such as voice.synthesize", required: true,
                                 cli: .positional),
                CommandParameter("provider", .string, "Provider ID; the project's choice or the highest priority by default",
                                 cli: .option("provider")),
                CommandParameter("params", .object, "Request parameters (JSON object)", sensitive: true,
                                 cli: .option("params")),
            ],
            execution: .job),
    ]
}

/// The event types a plugin view understands (`PluginViewEvent.Kind`), for the command catalog, which cannot import
/// the plugin module.
public enum PluginViewEventKinds {
    public static let all = ["click", "change", "submit", "select", "action"]
}
