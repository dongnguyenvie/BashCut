import BashCutProject

extension CommandCatalog {
    /// Settings › Storage.
    static let storageSpecs: [CommandSpec] = [
        CommandSpec(
            "storage.get", .read,
            "What BashCut keeps on disk (Settings › Storage): plugin folders, each plugin's data and cache, the saved "
                + "plugin registry, this project's preview proxies and the audit log, with sizes and paths."),
        CommandSpec(
            "storage.clear", .edit,
            "Delete what can be made or downloaded again: plugin-cache (all plugins, or --plugin), registry, proxies "
                + "(made again on demand), or plugin-data --plugin ID (the plugin must be set up again).",
            parameters: [
                CommandParameter("target", .string, "What to clear", required: true,
                                 choices: ["plugin-cache", "plugin-data", "registry", "proxies"], cli: .positional),
                CommandParameter("plugin", .string, "Only this plugin's data or cache", cli: .option("plugin")),
            ])
    ]
}
