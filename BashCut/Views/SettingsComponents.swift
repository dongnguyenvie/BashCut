import BashCutDocument
import SwiftUI

// Settings building blocks: section cards with rows (label left, control right, an optional description under
// the label), filtered by the search box at the top of Settings. Rows hide themselves when they do not match;
// sections and pages count the rows still shown through `SettingsHits` and hide when none are left.

/// The search text and whether the enclosing section shows every row anyway (its title matched).
private struct SettingsQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct SettingsShowAllKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsQuery: String {
        get { self[SettingsQueryKey.self] }
        set { self[SettingsQueryKey.self] = newValue }
    }

    fileprivate var settingsShowAll: Bool {
        get { self[SettingsShowAllKey.self] }
        set { self[SettingsShowAllKey.self] = newValue }
    }
}

/// The number of matching rows shown below a view while searching.
struct SettingsHits: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

extension SettingsSearch {
    /// The English source and the shown translation, so either language finds it.
    static func terms(_ resource: LocalizedStringResource?) -> [String] {
        guard let resource else { return [] }
        return [resource.key, String(localized: resource)]
    }
}

/// Whether a row with these search terms is shown; reports one hit while searching.
private struct SettingsFilter: ViewModifier {
    let terms: [String]
    @Environment(\.settingsQuery) private var query
    @Environment(\.settingsShowAll) private var showAll

    func body(content: Content) -> some View {
        if query.isEmpty {
            content
        } else if showAll || SettingsSearch.matches(query, terms) {
            content.preference(key: SettingsHits.self, value: 1)
        }
    }
}

extension View {
    /// Shown only when the search is empty or matches one of these terms (English source and translation).
    func settingsSearchable(_ terms: [String]) -> some View { modifier(SettingsFilter(terms: terms)) }

    /// Hidden while searching, unless its section matched by title: notes, filters and totals.
    func settingsHiddenWhileSearching() -> some View { modifier(SettingsHiddenWhileSearching()) }
}

private struct SettingsHiddenWhileSearching: ViewModifier {
    @Environment(\.settingsQuery) private var query
    @Environment(\.settingsShowAll) private var showAll

    func body(content: Content) -> some View {
        if query.isEmpty || showAll { content }
    }
}

/// A titled card of rows like a grouped form section, as wide as the page. Hidden while searching when none of
/// its rows match; a match on its title shows all of them.
struct SettingsSection<Content: View, Accessory: View, Footer: View>: View {
    private let title: String?
    private let terms: [String]
    private let symbol: String?
    private let content: Content
    private let accessory: Accessory
    private let footer: Footer
    @Environment(\.settingsQuery) private var query
    @State private var hits = 0

    init(
        _ title: LocalizedStringResource? = nil, symbol: String? = nil, @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title.map { String(localized: $0) }
        terms = SettingsSearch.terms(title)
        self.symbol = symbol
        self.content = content()
        self.accessory = accessory()
        self.footer = footer()
    }

    /// A section named by data that is already translated (a plugin category).
    init(verbatim title: String, symbol: String? = nil, @ViewBuilder content: () -> Content)
    where Accessory == EmptyView, Footer == EmptyView {
        self.title = title
        terms = [title]
        self.symbol = symbol
        self.content = content()
        accessory = EmptyView()
        footer = EmptyView()
    }

    private var titleMatches: Bool { title != nil && SettingsSearch.matches(query, terms) }
    private var hidden: Bool { !query.isEmpty && hits == 0 && !titleMatches }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hidden, title != nil || !(accessory is EmptyView) {
                HStack {
                    if let title {
                        Group {
                            if let symbol {
                                Label(title, systemImage: symbol)
                            } else {
                                Text(verbatim: title)
                            }
                        }.font(.headline)
                    }
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                content.environment(\.settingsShowAll, titleMatches && !query.isEmpty)
            }
            // The first row's separator sits above the card and is clipped away.
            .padding(.top, -1)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(hidden ? 0 : 0.1)))
            if !hidden, !(footer is EmptyView) {
                footer
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
        .onPreferenceChange(SettingsHits.self) { hits = $0 }
        .padding(.bottom, hidden ? 0 : 20)
    }
}

/// One setting: its title (and an optional description) on the left, the control on the right, with a separator
/// above it. Searchable by title, description and keywords.
struct SettingsRow<Control: View>: View {
    private let title: Text
    private let detail: Text?
    private let detailLines: Int?
    private let terms: [String]
    private let symbol: String?
    private let tint: Color?
    private let control: Control

    init(
        _ title: LocalizedStringResource, detail: LocalizedStringResource? = nil, keywords: [String] = [],
        symbol: String? = nil, tint: Color? = nil, @ViewBuilder control: () -> Control
    ) {
        self.title = Text(title)
        self.detail = detail.map { Text($0) }
        detailLines = nil
        terms = SettingsSearch.terms(title) + SettingsSearch.terms(detail) + keywords
        self.symbol = symbol
        self.tint = tint
        self.control = control()
    }

    /// A row whose title is already translated or is a name (plugins, files); `detailLines` truncates a path.
    init(
        verbatim title: String, detail: String? = nil, detailLines: Int? = nil, keywords: [String] = [],
        @ViewBuilder control: () -> Control
    ) {
        self.title = Text(verbatim: title)
        self.detail = detail.map { Text(verbatim: $0) }
        self.detailLines = detailLines
        terms = [title, detail ?? ""] + keywords
        symbol = nil
        tint = nil
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let symbol {
                    Label { title } icon: { Image(systemName: symbol) }
                } else {
                    title
                }
                if let detail {
                    if let detailLines {
                        detail.font(.caption2).foregroundStyle(.secondary).lineLimit(detailLines).truncationMode(.middle)
                    } else {
                        detail.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(tint ?? .primary)
            Spacer(minLength: 12)
            control
        }
        .settingsRowStyle()
        .settingsSearchable(terms)
    }
}

/// A free row (a message, a list item, a disclosure) with the row padding and separator.
struct SettingsPlainRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).settingsRowStyle()
    }
}

extension View {
    fileprivate func settingsRowStyle() -> some View {
        padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 40)
            .overlay(alignment: .top) { Divider().padding(.leading, 12) }
    }
}

/// A row that opens to more rows (a plugin's options, a plugin's storage). Searchable by its title and the
/// terms of what is inside; opens by itself while a search matches inside it.
struct SettingsDisclosureRow<Label: View, Content: View>: View {
    private let terms: [String]
    private let external: Binding<Bool>?
    private let content: Content
    private let label: Label
    @State private var local = false
    @Environment(\.settingsQuery) private var query

    init(
        terms: [String], isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.terms = terms
        external = isExpanded
        self.content = content()
        self.label = label()
    }

    private var isExpanded: Binding<Bool> {
        query.isEmpty ? external ?? $local : .constant(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() } }
            .settingsRowStyle()
            if isExpanded.wrappedValue {
                // Everything inside shows when the title matched; otherwise each row filters itself.
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.leading, 18)
                    .environment(\.settingsShowAll, true)
            }
        }
        .settingsSearchable(terms)
    }
}

/// A switch on the right of a row: grouped forms show toggles as switches.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// Matching rows per Settings section while searching.
struct SettingsPageHits: PreferenceKey {
    static let defaultValue: [String: Int] = [:]
    static func reduce(value: inout [String: Int], nextValue: () -> [String: Int]) {
        value.merge(nextValue(), uniquingKeysWith: +)
    }
}

/// One Settings section in the search results: its title above its matching rows, hidden when none match.
struct SettingsSearchPage<Content: View>: View {
    let id: String
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @State private var hits = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hits > 0 {
                Label(LocalizedStringKey(title), systemImage: icon).font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 0) { content }
        }
        .padding(.bottom, hits > 0 ? 16 : 0)
        .onPreferenceChange(SettingsHits.self) { hits = $0 }
        .preference(key: SettingsPageHits.self, value: [id: hits])
    }
}
