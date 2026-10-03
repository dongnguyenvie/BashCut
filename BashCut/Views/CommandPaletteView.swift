import BashCutDocument
import SwiftUI

/// ⇧⌘P: search every menu-bar command by name and run it with Enter. Built from `MenuCatalog`.
struct CommandPaletteView: View {
    let close: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @State private var entries: [MenuCatalog.Entry] = []
    @FocusState private var focused: Bool

    private var matches: [MenuCatalog.Entry] { Array(MenuCatalog.filter(entries, query).prefix(80)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain).font(.title3).focused($focused)
                    .onSubmit(runSelected)
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onExitCommand(perform: close)
            }.padding(12)
            Divider()
            if matches.isEmpty {
                Text("No matching command").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                                row(entry, selected: index == selection)
                                    .onTapGesture { run(entry) }
                            }
                        }.padding(6)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selection) {
                        if matches.indices.contains(selection) { proxy.scrollTo(matches[selection].id) }
                    }
                }
            }
        }
        .frame(width: 580)
        .background(Color(red: 0.11, green: 0.115, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .onAppear {
            entries = MenuCatalog.entries()
            focused = true
        }
        .onChange(of: query) { selection = 0 }
    }

    private func row(_ entry: MenuCatalog.Entry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.title)
                Text(entry.path.joined(separator: " ▸ ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !entry.shortcut.isEmpty {
                Text(entry.shortcut).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15)))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .opacity(entry.enabled ? 1 : 0.4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.cyan.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !matches.isEmpty else { return .handled }
        selection = min(max(0, selection + step), matches.count - 1)
        return .handled
    }

    private func runSelected() {
        guard matches.indices.contains(selection) else { return }
        run(matches[selection])
    }

    private func run(_ entry: MenuCatalog.Entry) {
        guard entry.enabled else { return }
        close()
        // After the palette is gone, so a command that opens a sheet or moves focus is not fighting it.
        DispatchQueue.main.async { entry.run() }
    }
}

/// ⌘/: every shortcut in the menu bar, by menu, plus the keys that work only on the timeline.
struct ShortcutsView: View {
    let done: () -> Void
    @State private var query = ""
    @State private var entries: [MenuCatalog.Entry] = []

    private var sections: [(menu: String, entries: [MenuCatalog.Entry])] {
        let shown = MenuCatalog.filter(entries.filter { !$0.shortcut.isEmpty }, query)
        var order: [String] = []
        var groups: [String: [MenuCatalog.Entry]] = [:]
        for entry in shown {
            let menu = entry.path.first ?? ""
            if groups[menu] == nil { order.append(menu) }
            groups[menu, default: []].append(entry)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2)
                Spacer()
                TextField("Filter", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            List {
                ForEach(sections, id: \.menu) { section in
                    Section(section.menu) {
                        ForEach(section.entries) { entry in shortcutRow(Text(verbatim: entry.title), entry.shortcut) }
                    }
                }
                if query.isEmpty {
                    Section("Timeline") {
                        ForEach(MenuCatalog.timelineKeys, id: \.title) { key in shortcutRow(Text(LocalizedStringKey(key.title)), key.shortcut) }
                    }
                }
            }
            Text("Keys without ⌘ (Space, I, O, ←, ⌫…) act on the timeline or viewer; while you type in a field they type.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 560, height: 600).preferredColorScheme(.dark)
        .onAppear { entries = MenuCatalog.entries() }
    }

    private func shortcutRow(_ title: Text, _ shortcut: String) -> some View {
        HStack {
            title
            Spacer()
            Text(shortcut).foregroundStyle(.secondary).monospaced()
        }
    }
}
