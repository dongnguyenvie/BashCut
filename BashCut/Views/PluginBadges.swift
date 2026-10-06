import BashCutPlugin
import SwiftUI

/// A dependency's state in words people understand: available, installed by setup, or not possible on this Mac.
struct PluginDependencyBadge: View {
    let state: PluginDependencyStatus.State?
    let installable: Bool
    let checking: Bool

    var body: some View {
        if checking {
            Label("Checking…", systemImage: "hourglass").font(.caption2).foregroundStyle(.secondary)
        } else {
            switch state {
            case .notChecked?:
                Label("Checked after approval", systemImage: "lock").font(.caption2).foregroundStyle(.secondary)
            case .available?:
                Label("Available on this Mac", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
            case .missing? where installable, nil where installable:
                Label("Installed during setup", systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary)
            default:
                Label("Not available on this Mac", systemImage: "xmark.octagon.fill").font(.caption2).foregroundStyle(.orange)
                    .help("The plugin needs it but cannot install it; ask the plugin's author.")
            }
        }
    }
}

/// Who signed a registry archive: BashCut, a publisher the registry lists, or nobody.
struct PluginSignatureBadge: View {
    let trust: PluginPublisherTrust

    var body: some View {
        switch trust {
        case .firstParty:
            Label("Signed by BashCut", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.cyan)
        case .verifiedPublisher(let publisher):
            Label(String(format: String(localized: "Signed by %@"), publisher), systemImage: "checkmark.seal")
                .font(.caption).foregroundStyle(.green)
        case .unsigned:
            Label("Not signed: only the checksum is verified. Install it only if you trust where it comes from.",
                  systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(.orange)
        }
    }
}
