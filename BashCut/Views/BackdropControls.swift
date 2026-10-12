import BashCutProject
import SwiftUI

/// Inspector › Video › Backdrop (P3-J7): what fills the frame around a fitted picture — a blurred copy of itself or
/// a colour — instead of black, without a second clip. Every change is `setBackdrop`, like `clip.backdrop`. With
/// several clips selected it shows the first one's backdrop (Mixed when they differ) and sets it on all of them.
struct BackdropControls: View {
    @Bindable var document: ProjectDocument
    let itemIDs: [String]

    init(document: ProjectDocument, item: Item) {
        self.document = document
        itemIDs = [item.id]
    }

    init(document: ProjectDocument, itemIDs: [String]) {
        self.document = document
        self.itemIDs = itemIDs
    }

    private var backdrops: [[String: JSONValue]?] {
        let items = document.project.tracks.flatMap(\.items)
        return itemIDs.map { id in items.first { $0.id == id }?["backdrop"]?.object }
    }

    private var backdrop: [String: JSONValue]? { backdrops.first ?? nil }

    var body: some View {
        let kind = backdrop?["kind"]?.string ?? "none"
        let all = backdrops
        if all.contains(where: { $0 != all.first ?? nil }) {
            Text("Backdrop: mixed").font(.caption).foregroundStyle(.secondary)
        }
        Picker("Backdrop", selection: Binding(
            get: { kind },
            set: { value in
                guard value != kind else { return }
                apply(value == "none" ? nil : (backdrop ?? [:]).merging(["kind": .string(value)]) { $1 })
            })
        ) {
            Text("None").tag("none")
            Text("Blur fill").tag("blur")
            Text("Colour").tag("color")
        }
        .help("Fills the frame around a fitted photo or clip with a blurred copy of it or a colour")
        if kind == "blur" {
            slider("Blur", key: "blur", fallback: 0.05, range: 0...0.2)
        }
        if kind == "color" {
            ColorPicker("Backdrop colour", selection: Binding(
                get: { Color(hex: backdrop?["color"]?.string ?? "#000000") },
                set: { apply((backdrop ?? [:]).merging(["color": .string($0.hex)]) { $1 }, coalesce: true) }),
                supportsOpacity: false)
        }
        if kind != "none" {
            slider("Dim", key: "dim", fallback: 0, range: 0...1)
        }
    }

    private func slider(_ title: LocalizedStringKey, key: String, fallback: Double, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: Binding(
                get: { backdrop?[key]?.double ?? fallback },
                set: { apply((backdrop ?? [:]).merging([key: .number(($0 * 1_000).rounded() / 1_000)]) { $1 }, coalesce: true) }),
                in: range)
        }
    }

    private func apply(_ value: [String: JSONValue]?, coalesce: Bool = false) {
        do { try document.setBackdrop(value, items: itemIDs, coalesce: coalesce) } catch {
            document.message = error.localizedDescription
        }
    }
}
