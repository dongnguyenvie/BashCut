import BashCutImport
import SwiftUI

struct LegacyEDLImportReportView: View {
    let report: LegacyEDLImportReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EDL import report").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Metric").fontWeight(.semibold)
                    Text("EDL").fontWeight(.semibold)
                    Text("BashCut").fontWeight(.semibold)
                }
                Divider().gridCellColumns(3)
                GridRow {
                    Text("Cuts")
                    Text(report.sourceCutCount, format: .number)
                    Text(report.importedCutCount, format: .number)
                }
                GridRow {
                    Text("Voiceovers")
                    Text(report.sourceVoiceoverCount, format: .number)
                    Text(report.importedVoiceoverCount, format: .number)
                }
                GridRow {
                    Text("Duration (frames)")
                    Text(report.sourceTotalFrames.map(String.init) ?? "—")
                    Text(report.importedDuration, format: .number)
                }
            }
            if report.sourceTotalFrames != nil && report.sourceTotalFrames != report.importedDuration {
                Label("Imported duration differs from the EDL total.", systemImage: "exclamationmark.triangle")
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
