import BashCutAgent
import SwiftUI

/// The composer's Templates button: the templates by group, the ones that fit the project first. Picking one puts
/// its filled request in the message.
struct BriefTemplatesMenu: View {
    let state: BriefFit
    let pick: (BriefTemplate) -> Void

    var body: some View {
        Menu {
            ForEach(BriefCatalog.sections(for: state), id: \.group) { section in
                Section(section.group.title) {
                    let fitting = section.templates.filter { $0.fits(state) }
                    ForEach(fitting) { item($0) }
                    if !fitting.isEmpty, fitting.count < section.templates.count { Divider() }
                    ForEach(section.templates.filter { !$0.fits(state) }) { item($0) }
                }
            }
        } label: {
            Label("Templates", systemImage: "list.bullet.rectangle")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Start the message from a template (or type / at the start)")
    }

    private func item(_ template: BriefTemplate) -> some View {
        Button {
            pick(template)
        } label: {
            Label(template.title, systemImage: template.systemImage)
        }
    }
}

/// A small composer button: icon and label, highlighted while on.
struct ComposerChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    var on = false
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        let fill: Color = on ? Color.cyan.opacity(0.18) : Color.white.opacity(0.05)
        let stroke: Color = on ? Color.cyan.opacity(0.6) : Color.white.opacity(0.1)
        let tint: Color = on ? .cyan : Color.primary.opacity(0.8)
        return Button(action: action) {
            Group {
                if showsTitle { Label(title, systemImage: systemImage) } else { Image(systemName: systemImage) }
            }
            .font(.caption).lineLimit(1)
                .padding(.horizontal, 7).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(stroke))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The "fits" mark on a template that suits the open project.
struct BriefFitBadge: View {
    var body: some View {
        Text("FITS").font(.system(size: 9, weight: .bold).monospaced()).foregroundStyle(.cyan)
            .help("Suits the open project")
    }
}
