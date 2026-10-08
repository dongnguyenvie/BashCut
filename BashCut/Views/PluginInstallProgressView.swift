import SwiftUI

/// Install or setup progress: the current step, a bar when the recipe reports `::progress`, Cancel and the output.
struct PluginInstallProgressView: View {
    @Bindable var model: PluginManagerModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let batch = model.installBatch { Text(batch).font(.caption.bold()) }
            HStack {
                if let progress = model.installProgress {
                    ProgressView(value: progress) { Text(model.installStep).font(.caption) }
                } else {
                    ProgressView { Text(model.installStep).font(.caption) }.progressViewStyle(.linear)
                }
                Button("Cancel", role: .cancel, action: model.cancelInstall).disabled(model.installJob == nil)
            }
            if let last = model.installLog.last {
                Text(last).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if !model.installLog.isEmpty {
                RowDisclosureGroup("Output", isExpanded: $showLog) {
                    ScrollView {
                        Text(model.installLog.suffix(200).joined(separator: "\n")).font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(height: 120)
                }.font(.caption)
            }
        }.padding(8).background(.white.opacity(0.04)).cornerRadius(6)
    }
}
