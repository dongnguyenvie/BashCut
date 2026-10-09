import BashCutAutomation
import BashCutDocument
import BashCutProject
import BashCutPlugin
import BashCutPlugins
import Foundation

/// An install asked for while another was in progress, shown when it ends.
enum PluginInstallRequest: Equatable {
    case plugin(id: String, version: String?)
    case bundle(id: String, only: [String]?)
    /// Running an installed plugin's setup again: a dependency was still missing after its install.
    case setup(id: String)

    var name: String {
        switch self {
        case .plugin(let id, _), .bundle(let id, _), .setup(let id): id
        }
    }
}

/// What asking for an install did: its approval is showing, it waits behind another install, or (a bundle) every
/// plugin in it is already installed.
enum PluginInstallRequestOutcome: Equatable {
    case pending
    case queued(position: Int)
    case nothingToInstall

    var json: [String: JSONValue] {
        switch self {
        case .pending: ["approval": .string("pending")]
        case .queued(let position): ["approval": .string("queued"), "position": .integer(position)]
        case .nothingToInstall: ["approval": .string("none"), "reason": .string("Everything in it is installed")]
        }
    }
}

/// One plugin of a bundle as this Mac sees it: what installing would do, or why it is left out.
struct PluginBundleMember: Identifiable {
    let member: PluginRegistryBundle.Member
    /// nil when the registry no longer lists the plugin.
    let listing: PluginListing?
    var id: String { member.id }
    var name: String { listing?.entry.name.text ?? member.id }

    /// Only plugins this Mac does not have yet; updates stay in Updates.
    var installable: Bool { listing?.status == .available }

    /// Why the plugin is not offered, or nil when it is.
    var reason: String? {
        guard let listing else { return String(localized: "Not in the plugin registry") }
        switch listing.status {
        case .available: return nil
        case .installed, .update: return String(localized: "Installed")
        case .shadowed: return String(localized: "Installed in this project or the app")
        case .incompatible(let reason): return reason
        }
    }

    var json: JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(id), "name": .string(name), "default": .bool(member.checkedByDefault),
            "installable": .bool(installable), "status": .string(listing?.statusName ?? "missing"),
        ]
        if let reason { fields["reason"] = .string(reason) }
        if let size = listing?.version?.size { fields["size"] = .integer(size) }
        if let setup = listing?.version?.downloadBytes, setup > 0 { fields["setupBytes"] = .integer(setup) }
        return .object(fields)
    }
}

/// A bundle waiting for the user's approval: the verified downloads, each with a checkbox, and the plugins left out.
struct PendingBundleInstall: Identifiable {
    struct Item: Identifiable {
        var pending: PendingPluginInstall
        var selected: Bool
        var id: String { pending.plugin.id }
    }

    struct Skipped: Identifiable {
        let id: String
        let name: String
        let reason: String
    }

    let id = UUID()
    let bundle: PluginRegistryBundle
    var items: [Item]
    let skipped: [Skipped]
    var selected: [PendingPluginInstall] { items.filter(\.selected).map(\.pending) }
}

/// Plugin bundles (Recommended): one approval for several registry plugins, and the queue that keeps one install
/// approval or run at a time.
extension PluginManagerModel {
    /// Something is downloading for an approval, waiting for one, or installing.
    var installBusy: Bool {
        installing || pendingInstall != nil || pendingBundle != nil || !downloading.isEmpty || addingLink
    }

    /// Refuses an install that cannot wait in the queue (a plugin from this Mac or a link, a setup).
    func checkNotBusy() throws {
        guard installBusy else { return }
        throw PluginError.invalid("Another plugin install is in progress; try again when it finishes")
    }

    /// Queues `request` when another install is in progress: its place in the queue (from 1), or nil to start now.
    func enqueueIfBusy(_ request: PluginInstallRequest) -> Int? {
        guard installBusy else { return nil }
        if let index = installQueue.firstIndex(of: request) { return index + 1 }
        installQueue.append(request)
        return installQueue.count
    }

    /// Shows the next queued install once nothing else is in progress.
    func advanceInstallQueue() {
        guard !installBusy, !installQueue.isEmpty else { return }
        let next = installQueue.removeFirst()
        Task { [weak self] in
            guard let self else { return }
            do {
                switch next {
                case .plugin(let id, let version): try await requestInstall(id, version: version)
                case .bundle(let id, let only): try await requestBundle(id, only: only)
                case .setup(let id):
                    guard let plugin = plugin(id) else { break }
                    try requestSetup(plugin)
                }
            } catch {
                message = next.name + ": " + error.localizedDescription
            }
            advanceInstallQueue()
        }
    }

    /// The last health check ran a dependency's probe and it failed, and the dependency has an install recipe.
    /// A dependency not checked (the plugin was not ready yet, for example just after its install) does not count.
    func needsSetup(_ plugin: InstalledPlugin) -> Bool {
        guard let health = health[plugin.id] else { return false }
        return health.dependencies.contains { status in
            status.state == .missing && plugin.manifest.dependencies.contains { $0.id == status.id && $0.install != nil }
        }
    }

    /// After installs end, checks the plugins' health again and queues the setup approval (Install Dependencies)
    /// of each one whose dependency is still missing, so the user only has to approve it. Setup never runs
    /// without that approval.
    func offerSetupIfNeeded(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            var missing: [String] = []
            for id in ids {
                guard let plugin = plugin(id) else { continue }
                let result = await checkHealthNow(plugin)
                DebugLog.write("plugin", "after install \(id): " + result.dependencies
                    .map { "\($0.id) \($0.state.rawValue) \($0.detail)" }.joined(separator: "; "))
                guard needsSetup(plugin) else { continue }
                missing.append(plugin.manifest.displayName)
                if !installQueue.contains(.setup(id: id)) { installQueue.append(.setup(id: id)) }
            }
            if !missing.isEmpty {
                message = String(format: String(localized: "%@ still needs setup: review Install Dependencies"),
                                 missing.joined(separator: ", "))
            }
            advanceInstallQueue()
        }
    }

    /// The plugins of `bundle` in its order, with what installing each would do on this Mac.
    func members(of bundle: PluginRegistryBundle) -> [PluginBundleMember] {
        bundle.plugins.map { member in
            PluginBundleMember(member: member, listing: registry?.entry(member.id).map(listing))
        }
    }

    /// Bundles with at least one plugin this Mac can still install, for the Recommended card.
    var offeredBundles: [PluginRegistryBundle] {
        (registry?.bundles ?? []).filter { members(of: $0).contains(where: \.installable) }
    }

    /// Downloads and verifies every plugin of a bundle this Mac does not have, then shows one approval listing them
    /// with a checkbox each (`only` checks exactly those, otherwise each plugin's default). Nothing runs before the
    /// user approves it.
    @discardableResult
    func requestBundle(_ id: String, only: [String]? = nil) async throws -> PluginInstallRequestOutcome {
        guard PluginChannel.current.allowsUserPlugins else { throw PluginError.invalid(Self.channelRefusal) }
        if registry == nil { await refreshRegistry() }
        guard let bundle = registry?.bundle(id) else { throw PluginError.invalid("No bundle \(id) in the registry") }
        let unknown = (only ?? []).filter { plugin in !bundle.plugins.contains { $0.id == plugin } }
        guard unknown.isEmpty else {
            throw PluginError.invalid("\(unknown.joined(separator: ", ")) is not in \(id)")
        }
        if let position = enqueueIfBusy(.bundle(id: id, only: only)) { return .queued(position: position) }
        let members = members(of: bundle)
        let offered = members.filter(\.installable)
        guard !offered.isEmpty else {
            message = String(format: String(localized: "Everything in %@ is installed"), bundle.name.text)
            return .nothingToInstall
        }
        let ids = Set(offered.map(\.id))
        downloading.formUnion(ids)
        defer {
            downloading.subtract(ids)
            advanceInstallQueue()
        }
        let skipped = members.compactMap { member in
            member.reason.map { PendingBundleInstall.Skipped(id: member.id, name: member.name, reason: $0) }
        }
        let (items, failed) = try await stage(offered, only: only)
        guard !items.isEmpty else {
            throw PluginError.invalid(failed.map { "\($0.name): \($0.reason)" }.joined(separator: "; "))
        }
        pendingBundle = PendingBundleInstall(bundle: bundle, items: items, skipped: skipped + failed)
        tab = .browse
        return .pending
    }

    /// Downloads and verifies each offered plugin in turn; one that fails is left out with its error.
    private func stage(
        _ offered: [PluginBundleMember], only: [String]?
    ) async throws -> ([PendingBundleInstall.Item], [PendingBundleInstall.Skipped]) {
        var items: [PendingBundleInstall.Item] = []
        var skipped: [PendingBundleInstall.Skipped] = []
        for member in offered {
            guard let listing = member.listing, let version = listing.version else { continue }
            do {
                let staged = try await registryInstaller.stage(
                    listing.entry, version: version, publisherKeys: registry?.keys(for: listing.entry.publisher) ?? [])
                items.append(.init(pending: pendingRegistryInstall(staged),
                                   selected: only.map { $0.contains(member.id) } ?? member.member.checkedByDefault))
            } catch {
                if error is CancellationError {
                    items.forEach { $0.pending.archive?.discard() }
                    throw error
                }
                skipped.append(.init(id: member.id, name: member.name, reason: error.localizedDescription))
            }
        }
        return (items, skipped)
    }

    /// Drops the bundle waiting for approval and its downloads, then shows the next queued install.
    func cancelPendingBundle() {
        pendingBundle?.items.forEach { $0.pending.archive?.discard() }
        pendingBundle = nil
        advanceInstallQueue()
    }

    /// Bytes the checked plugins of the pending bundle need.
    func requiredBytes(_ bundle: PendingBundleInstall) -> Int64 { bundle.selected.map(requiredBytes).reduce(0, +) }

    /// Why the pending bundle cannot start (nothing checked, or not enough free space), or nil.
    func installBlocker(_ bundle: PendingBundleInstall) -> String? {
        if bundle.selected.isEmpty { return String(localized: "Choose at least one plugin") }
        let needed = requiredBytes(bundle)
        guard needed > 0, let free = PluginFolders.availableBytes(), Double(needed) * 1.2 > Double(free) else { return nil }
        let format = ByteCountFormatter()
        return String(
            format: String(localized: "Needs about %@ but only %@ is free"),
            format.string(fromByteCount: needed), format.string(fromByteCount: free))
    }

    /// Installs the checked plugins of the approved bundle one after another, as one job with progress and Cancel.
    /// Each is installed like a single approved plugin (recipes, then trust); one that fails is reported and the
    /// rest go on.
    func installPendingBundle() {
        guard let approved = pendingBundle, !installing else { return }
        if let blocker = installBlocker(approved) {
            message = blocker
            return
        }
        let chosen = approved.selected
        approved.items.filter { !$0.selected }.forEach { $0.pending.archive?.discard() }
        pendingBundle = nil
        let bundleName = approved.bundle.name.text
        let results = BundleResults()
        installing = true
        installProgress = nil
        installLog = []
        installStep = String(localized: "Installing…")
        let work: @MainActor (JobReporter?) async throws -> JSONValue = { [weak self] reporter in
            guard let self else { throw CancellationError() }
            for (index, pending) in chosen.enumerated() {
                try Task.checkCancellation()
                let name = pending.plugin.manifest.displayName
                installBatch = String(format: String(localized: "%@: %d of %d"), bundleName, index + 1, chosen.count)
                installStep = String(format: String(localized: "Installing %@…"), name)
                installProgress = nil
                reporter?.detail("\(installBatch ?? "") \(name)")
                do {
                    try await performInstall(pending, reporter: reporter)
                    results.installed.append(pending.plugin.id)
                } catch {
                    if JobCenter.isCancellation(error) { throw error }
                    results.failed.append((name, error.localizedDescription))
                    installLog.append("\(name): \(error.localizedDescription)")
                }
                pending.archive?.discard()
            }
            return .object([
                "bundle": .string(approved.bundle.id), "installed": .array(results.installed.map(JSONValue.string)),
                "failed": .array(results.failed.map { .object(["plugin": .string($0.name), "error": .string($0.error)]) }),
            ])
        }
        let finished: @MainActor (Result<JSONValue, any Error>) -> Void = { [weak self] outcome in
            guard let self else { return }
            installing = false
            installJob = nil
            installBatch = nil
            chosen.forEach { $0.archive?.discard() }
            message = results.summary(outcome, of: chosen.count, bundle: bundleName)
            refresh(projectRoot: currentProjectRoot)
            results.installed.forEach(offerMissingRequirements(of:))
            offerSetupIfNeeded(results.installed)
            advanceInstallQueue()
        }
        if let jobs {
            installJob = jobs.start(
                "plugins.install", author: .user, detail: bundleName,
                work: { reporter in try await work(reporter) }, finished: finished)
        } else {
            Task { do { finished(.success(try await work(nil))) } catch { finished(.failure(error)) } }
        }
    }
}

/// What a bundle install did so far, kept apart from the job's result so Cancel can still say it.
@MainActor private final class BundleResults {
    var installed: [String] = []
    var failed: [(name: String, error: String)] = []

    /// What the Plugins sheet says when the bundle install ends.
    func summary(_ outcome: Result<JSONValue, any Error>, of count: Int, bundle: String) -> String {
        switch outcome {
        case .failure(let error) where JobCenter.isCancellation(error):
            String(format: String(localized: "Stopped after installing %d of %d plugins"), installed.count, count)
        case .failure(let error):
            error.localizedDescription
        case .success where failed.isEmpty:
            String(format: String(localized: "%@ is installed"), bundle)
        case .success:
            String(format: String(localized: "Installed %d of %d plugins. %@"), installed.count, count,
                   failed.map { "\($0.name): \($0.error)" }.joined(separator: "; "))
        }
    }
}
