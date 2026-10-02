import BashCutProject
import SwiftUI

/// What a timeline import (such as a legacy edl.json) brought over, next to what the source stated.
struct TimelineImportReportView: View {
    let report: TimelineImport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(report.title)).font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Metric").fontWeight(.semibold)
                    Text(LocalizedStringKey(report.sourceName)).fontWeight(.semibold)
                    Text("BashCut").fontWeight(.semibold)
                }
                Divider().gridCellColumns(3)
                ForEach(report.counts, id: \.key) { count in
                    GridRow {
                        Text(LocalizedStringKey(count.label))
                        Text(count.source.map(String.init) ?? "—")
                        Text(count.imported, format: .number)
                    }
                }
            }
            if let note = report.mismatchNote {
                Label(LocalizedStringKey(note), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !report.warnings.isEmpty {
                Text("Needs manual review").font(.headline)
                ForEach(report.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 300)
    }
}
