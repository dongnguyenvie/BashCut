import SwiftUI

struct WelcomeView: View {
    @Bindable var document: ProjectDocument

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Image(systemName: "scissors")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text("BashCut").font(.largeTitle.bold())
                Text("Build a cut with layered video, images, captions, audio and your preferred agent.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("New project", action: document.newProject)
                        .buttonStyle(.borderedProminent).keyboardShortcut("n")
                    Button("Open project…", action: document.openProject).keyboardShortcut("o")
                }
                Button("Import from edl.json…", action: document.importLegacyEDL)
                Spacer()
            }
            .frame(maxWidth: 440, maxHeight: .infinity, alignment: .leading)
            .padding(56)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent projects").font(.headline)
                    Spacer()
                    if !document.recentProjectURLs.isEmpty {
                        Button("Clear", action: document.clearRecentProjects).buttonStyle(.plain)
                    }
                }
                if document.recentProjectURLs.isEmpty {
                    ContentUnavailableView(
                        "No recent projects", systemImage: "clock",
                        description: Text("Projects you open or create will appear here."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(document.recentProjectURLs, id: \.path) { url in
                                Button { document.openProject(at: url) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "film.stack").foregroundStyle(.cyan)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(url.deletingPathExtension().lastPathComponent)
                                                .font(.body.weight(.medium)).lineLimit(1)
                                            Text(url.deletingLastPathComponent().path)
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
            .frame(width: 480)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.065, green: 0.07, blue: 0.08))
    }
}
