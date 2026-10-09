import AppKit
import SwiftUI

/// A workflow gate waiting for the user (P1-D5): the agent's summary and attachments, answered only here.
struct CheckpointView: View {
    let request: CheckpointRequest
    let resolve: (CheckpointRequest.Status, String?) -> Void
    @State private var note = ""

    private var images: [URL] {
        request.attachments.filter { ["png", "jpg", "jpeg", "heic", "tiff"].contains($0.pathExtension.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.gate.label, systemImage: "hand.raised")
                .font(.title2.bold())
            Text("\(request.author.rawValue.capitalized) is waiting for your answer. Revision \(request.revision).")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(request.summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
            if !images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { url in
                            if let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFit().frame(height: 160)
                                    .onTapGesture { NSWorkspace.shared.open(url) }
                                    .help(url.lastPathComponent)
                            }
                        }
                    }
                }
            }
            ForEach(request.attachments.filter { !images.contains($0) }, id: \.self) { url in
                Button(url.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
            }
            TextField("Note for the agent (optional)", text: $note, axis: .vertical).lineLimit(2...5)
            HStack {
                Button("Reject") { resolve(.rejected, note) }
                Spacer()
                Button("Ask for changes") { resolve(.changes, note) }.keyboardShortcut(.cancelAction)
                Button("Approve") { resolve(.approved, note) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 640).interactiveDismissDisabled()
    }
}
