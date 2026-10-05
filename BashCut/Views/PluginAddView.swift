import BashCutPlugin
import SwiftUI

/// Add Plugin…: paste a link from the plugin's author (a zip, a GitHub repo or folder, a release, a plugin.json),
/// or choose a plugin on this Mac. Either way the install approval follows; nothing runs before it.
struct PluginAddView: View {
    @Bindable var model: PluginManagerModel
    @State private var link = ""
    @State private var sha256 = ""
    @State private var token = ""
    @State private var editingToken = false
    @State private var error: String?

    private var parsed: Result<PluginLink, any Error>? {
        let text = link.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Result { try PluginLink(parsing: text, sha256: sha256.trimmingCharacters(in: .whitespaces)) }
    }

    private var validLink: PluginLink? { if case .success(let link)? = parsed { link } else { nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add Plugin", systemImage: "puzzlepiece.extension").font(.title2)
            Text("Paste a link from the plugin's author, or choose a plugin on this Mac. These plugins are not from the "
                + "BashCut registry: you see what they do and approve them before they run.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Link", text: $link, prompt: Text(verbatim: "https://github.com/user/my-plugin"))
                .textFieldStyle(.roundedBorder).onSubmit(download)
            linkSummary
            TextField("SHA-256 (optional)", text: $sha256, prompt: Text("SHA-256 (optional)"))
                .textFieldStyle(.roundedBorder).font(.caption.monospaced())
            if let link = validLink { tokenRow(host: link.tokenHost) }
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Choose File or Folder…", action: model.chooseLocalPlugin).disabled(model.addingLink)
                Spacer()
                if model.addingLink { ProgressView().controlSize(.small) }
                Button("Cancel") { model.showAddPlugin = false }.keyboardShortcut(.cancelAction)
                Button("Download", action: download).buttonStyle(.borderedProminent)
                    .disabled(validLink == nil || model.addingLink)
            }
        }.padding(20).frame(width: 520).preferredColorScheme(.dark)
    }

    @ViewBuilder private var linkSummary: some View {
        switch parsed {
        case .failure(let failure)?:
            Text(failure.localizedDescription).font(.caption).foregroundStyle(.orange)
        case .success(let link)?:
            Text(Self.describe(link)).font(.caption).foregroundStyle(.secondary)
        case nil:
            Text("A .zip or .bashcutplugin link, a GitHub repo (or a folder or plugin.json in it), or a GitHub release")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func describe(_ link: PluginLink) -> String {
        switch link.target {
        case .archive(let url):
            String(format: String(localized: "Archive %@ from %@"), url.lastPathComponent, url.host ?? "")
        case .githubRepo(let owner, let repo, let ref, let path):
            String(format: String(localized: "GitHub repo %@ at %@"), "\(owner)/\(repo)" + (path.map { "/" + $0 } ?? ""),
                   ref ?? String(localized: "the default branch"))
        case .githubRelease(let owner, let repo, let tag):
            String(format: String(localized: "GitHub release %@ of %@"), tag ?? String(localized: "latest"), "\(owner)/\(repo)")
        }
    }

    @ViewBuilder private func tokenRow(host: String) -> some View {
        let saved = model.hasLinkToken(for: host)
        if editingToken {
            HStack {
                SecureField(String(format: String(localized: "Access token for %@"), host), text: $token)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveToken(host: host) }.disabled(token.isEmpty)
                if saved { Button("Remove", role: .destructive) { token = ""; saveToken(host: host) } }
                Button("Cancel") { editingToken = false; token = "" }
            }
            Text("Kept in the Keychain on this Mac and sent only to \(host). Needed for private repos and links.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            HStack {
                Label(saved ? String(format: String(localized: "Access token for %@ is saved"), host)
                            : String(format: String(localized: "No access token for %@ (only needed for private links)"), host),
                      systemImage: saved ? "key.fill" : "key")
                    .font(.caption).foregroundStyle(.secondary)
                Button(saved ? "Change…" : "Add Token…") { editingToken = true }.buttonStyle(.link).font(.caption)
            }
        }
    }

    private func saveToken(host: String) {
        do {
            try model.setLinkToken(token, for: host)
            token = ""
            editingToken = false
        } catch { self.error = error.localizedDescription }
    }

    private func download() {
        guard let link = validLink, !model.addingLink else { return }
        error = nil
        Task {
            do { try await model.requestLinkInstall(link) } catch { self.error = error.localizedDescription }
        }
    }
}
