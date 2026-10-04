import AppKit
import BashCutDocument
import SwiftUI

/// Software Update: this BashCut's version and whether a newer release is out, opened from the menus or by itself
/// when a project opens and a new release is known. It never installs anything: Homebrew copies get the
/// `brew upgrade` command, downloaded copies the release page.
struct AppUpdateView: View {
    let model: AppUpdateModel
    @Bindable var settings: SettingsModel
    let check: () -> Void
    let skip: () -> Void
    let later: () -> Void
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .available(let release) = model.status {
                available(release)
            } else {
                HStack {
                    Label("Software Update", systemImage: "arrow.down.circle").font(.title2.bold())
                    Spacer()
                    Button("Check Again", action: check)
                        .disabled(model.status == .checking || !model.install.checksForUpdates)
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
                LabeledContent("This version") {
                    Text(verbatim: "BashCut \(model.version) (\(model.build)) · \(installName)").textSelection(.enabled)
                }
                status
                Spacer(minLength: 0)
            }
            if model.install.checksForUpdates {
                Toggle("Check for BashCut updates daily", isOn: $settings.checkAppUpdatesDaily).font(.caption)
            }
        }
        .padding(20).frame(width: 560, height: 440, alignment: .top).preferredColorScheme(.dark)
    }

    @ViewBuilder private var status: some View {
        switch model.status {
        case .idle, .checking:
            ProgressView("Checking for updates…")
        case .upToDate:
            Label("BashCut is up to date.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if let checkedAt = model.checkedAt {
                Text(String(format: String(localized: "Checked %@"), checkedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).textSelection(.enabled)
        case .available:
            EmptyView()
        }
    }

    /// The update prompt: what is new, how to update, and Skip This Version / Remind Me Later.
    @ViewBuilder private func available(_ release: AppRelease) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of BashCut is available!").font(.title3.bold())
                Text(String(format: String(localized: "BashCut %@ is now available. You have %@."),
                            release.version, model.version))
                    .foregroundStyle(.secondary)
            }
        }
        if let notes = release.notes {
            Text("Release notes:").font(.caption.bold())
            ScrollView {
                Text(notes).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
        } else {
            Spacer(minLength: 0)
        }
        if let command = model.upgradeCommand {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quit BashCut, then run in Terminal:").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: command).font(.body.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
            }
        }
        HStack {
            if settings.appUpdateDismissed != release.version {
                Button("Skip This Version", action: skip)
                    .help("No reminders for this version; a newer release shows again")
            }
            Spacer()
            if settings.appUpdateDismissed != release.version {
                Button("Remind Me Later", action: later).help("Ask again tomorrow")
            } else {
                Button("Done", action: done)
            }
            if let command = model.upgradeCommand {
                Button("Release Notes…") { NSWorkspace.shared.open(release.url) }
                Button(copied ? "Copied" : "Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Download…") {
                    NSWorkspace.shared.open(release.url)
                    done()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var installName: String {
        switch model.install {
        case .homebrew: String(localized: "Homebrew")
        case .direct: String(localized: "Downloaded")
        case .appStore: String(localized: "App Store")
        case .development: String(localized: "Development build")
        }
    }
}
