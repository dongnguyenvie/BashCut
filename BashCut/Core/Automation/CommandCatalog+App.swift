import BashCutProject

extension CommandCatalog {
    /// BashCut itself: its version and whether a newer release is out (BashCut › Check for Updates…).
    static let appSpecs: [CommandSpec] = [
        CommandSpec(
            "app.version", .read,
            "This BashCut's version and build, how it was installed (homebrew, direct, app-store, development) and "
                + "the plugin API it offers, like About BashCut."),
        CommandSpec(
            "app.update-check", .read,
            "Ask GitHub for the latest BashCut release, like BashCut › Check for Updates…. Returns this version, the "
                + "latest release (version, page, notes) when it is newer, and how to update: the Homebrew command or "
                + "the release page, and canUpdateNow when app update can install it. Never installs anything; App "
                + "Store and TestFlight copies are not checked."),
        CommandSpec(
            "app.update", .privileged,
            "Update a Homebrew copy of BashCut to the release app update-check found, like Update Now in Software "
                + "Update; the user approves it in the app first. Homebrew downloads the release while BashCut runs, "
                + "then BashCut saves the project, quits, upgrades (brew upgrade --cask bashcut) and opens again. A "
                + "failure keeps BashCut running: app update-check reports it as installError. Downloaded copies "
                + "update from the release page.",
            execution: .approval),
    ]
}
