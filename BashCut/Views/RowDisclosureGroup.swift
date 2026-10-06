import SwiftUI

/// A disclosure group whose whole title row opens and closes it, not only the chevron.
struct RowDisclosureGroup<Label: View, Content: View>: View {
    private let external: Binding<Bool>?
    @State private var local = false
    private let content: () -> Content
    private let label: () -> Label

    init(
        isExpanded: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        external = isExpanded
        self.content = content
        self.label = label
    }

    private var isExpanded: Binding<Bool> { external ?? $local }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded, content: content) {
            HStack(spacing: 0) {
                label()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() } }
        }
    }
}

extension RowDisclosureGroup where Label == Text {
    init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }
}
