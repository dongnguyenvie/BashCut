import SwiftUI

struct DoctorView: View {
    @Bindable var model: DoctorModel
    let refresh: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Doctor", systemImage: summaryIcon).font(.title2.bold())
                    .foregroundStyle(summaryColor)
                Spacer()
                Button("Run again", action: refresh).disabled(model.running)
                Button("Done", action: done)
            }
            Text("Checks the current workspace, agent CLIs, automation socket and optional plugin dependencies.")
                .font(.caption).foregroundStyle(.secondary)
            List(model.checks) { check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(check.state)).foregroundStyle(color(check.state))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(check.title)).font(.headline)
                        Text(check.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }.padding(.vertical, 3)
            }
            if model.running { ProgressView("Checking plugin dependencies…") }
        }.padding(20).frame(width: 720, height: 580, alignment: .top).preferredColorScheme(.dark)
    }

    private var summaryIcon: String { icon(model.summary) }
    private var summaryColor: Color { color(model.summary) }
    private func icon(_ state: DoctorCheck.State) -> String {
        switch state {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }
    private func color(_ state: DoctorCheck.State) -> Color {
        switch state {
        case .pass: .green
        case .warning: .orange
        case .fail: .red
        }
    }
}
