import BashCutProject

extension CommandCatalog {
    /// Settings › Storage.
    static let storageSpecs: [CommandSpec] = [
        CommandSpec(
            "storage.get", .read,
            "What BashCut keeps on disk (Settings › Storage): each plugin's folder, data and cache, the saved "
                + "plugin registry, the shared plugin runtimes, this project's preview proxies, ramp audio and the audit log, with sizes and paths. "
                + "plugins lists each plugin's total, largest first."),
        CommandSpec(
            "storage.clear", .edit,
            "Delete what can be made or downloaded again: plugin-cache (all plugins, or --plugin), shared-cache, registry, "
                + "proxies or ramp-audio (made again on demand), plugin-data --plugin ID (the plugin must be set up again), "
                + "or shared-data (plugins using the shared runtimes must be set up again).",
            parameters: [
                CommandParameter("target", .string, "What to clear", required: true,
                                 choices: ["plugin-cache", "plugin-data", "shared-cache", "shared-data", "registry", "proxies",
                                           "ramp-audio"], cli: .positional),
                CommandParameter("plugin", .string, "Only this plugin's data or cache", cli: .option("plugin")),
            ])
    ]
}
