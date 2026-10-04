import BashCutAutomation
import BashCutStorage
import SwiftUI

struct WelcomeView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                // The mark and name as one lockup, without the app icon's tile, so it sits on the window
                // background; the tagline reads as a shell line, like the agent terminals beside the editor.
                HStack(spacing: 12) {
                    BashCutLogo(tile: false, waveforms: false).frame(width: 64, height: 64)
                    Text(verbatim: "BashCut").font(.system(size: 30, weight: .bold))
                }
                .padding(.leading, -8)
                .accessibilityElement(children: .combine)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "$").foregroundStyle(.cyan).accessibilityHidden(true)
                    Text("Build a cut with layered video, images, captions, audio and your preferred agent.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(.body, design: .monospaced))
                HStack {
                    Button("New project") { document.run(.newProject) }
                        .buttonStyle(.borderedProminent).action(.newProject, in: document)
                    Button("Open project…") { document.run(.openProject) }.action(.openProject, in: document)
                }
                Button("Import from edl.json…", action: document.importLegacyEDL)
                Spacer()
            }
            .frame(maxWidth: 440, maxHeight: .infinity, alignment: .leading)
            .padding(40)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent projects").font(.headline)
                    Spacer()
                    if !document.settings.recentProjects.isEmpty {
                        Button("Clear") { document.run(.clearRecentProjects) }.buttonStyle(.plain)
                    }
                }
                if document.settings.recentProjects.isEmpty {
                    ContentUnavailableView(
                        "No recent projects", systemImage: "clock",
                        description: Text("Projects you open or create will appear here."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(document.settings.recentProjects, id: \.path) { url in
                                Button { document.openProject(at: url) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "film.stack").foregroundStyle(.cyan)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(Self.projectName(url))
                                                .font(.body.weight(.medium)).lineLimit(1)
                                            Text(Self.projectLocation(url).path)
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.045))
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            // Narrower next to the agent dock.
            .frame(minWidth: 240, idealWidth: 480, maxWidth: 480)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.065, green: 0.07, blue: 0.08))
    }

    /// Every project file is `project.bashcut.json`, so a project is named by the folder that holds it.
    static func projectName(_ url: URL) -> String {
        isStandardProjectFile(url) ? url.deletingLastPathComponent().lastPathComponent
            : url.deletingPathExtension().lastPathComponent
    }

    /// Where the project lives: the folder that holds the project folder, beside the name.
    static func projectLocation(_ url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        return isStandardProjectFile(url) ? folder.deletingLastPathComponent() : folder
    }

    private static func isStandardProjectFile(_ url: URL) -> Bool {
        url.lastPathComponent == ProjectStorage.projectFileName
    }
}
