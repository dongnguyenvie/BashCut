import AppKit
import BashCutDocument
import BashCutEngine
import BashCutProject

extension ProjectDocument {
    func importColorLUT() {
        guard fileURL != nil else {
            message = String(localized: "Save the project before importing a LUT")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cube")].compactMap { $0 }
        guard let source = ModalCenter.shared.open(panel, name: "import-lut")?.first else { return }
        do {
            try importColorLUT(from: source)
            message = String(localized: "LUT imported")
        } catch { message = error.localizedDescription }
    }

    /// Checks a .cube file, copies it into the project's `luts` folder and adds it; returns the LUT.
    @discardableResult
    func importColorLUT(
        from source: URL, name: String? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, lut: ColorLUT) {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Save the project before importing a LUT")
        }
        let parsed = try CubeLUT.load(source)
        let id = UUID().uuidString
        let relative = "luts/\(id).cube"
        let destination = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // `.atomic` and `.withoutOverwriting` cannot be combined (Foundation traps); the name is new anyway.
        try Data(contentsOf: source).write(to: destination, options: .withoutOverwriting)
        let lut = ColorLUT(
            id: id, name: name ?? source.deletingPathExtension().lastPathComponent, path: relative,
            size: parsed.dimension)
        do {
            let revision = try commit(.addColorLUT(lut), label: "Import LUT", author: author, baseRevision: baseRevision)
            return (revision, lut)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Applies a LUT to the selected item, or adds an adjustment with it when nothing is selected.
    func applyColorLUT(_ id: String?) {
        guard selected != nil else {
            guard let id else { return }
            do { try addAdjustment(lutID: id) } catch { message = error.localizedDescription }
            return
        }
        var color = selected?["color"]?.object ?? [:]
        color["lut"] = id.map(JSONValue.string)
        if id == nil { color.removeValue(forKey: "lutStrength") }
        patchSelected(["color": .object(color)], label: id == nil ? "Remove LUT" : "Apply LUT")
    }

    func setColorLUTStrength(_ value: Double) {
        guard selected != nil else { return }
        var color = selected?["color"]?.object ?? [:]
        color["lutStrength"] = .number(min(1, max(0, value)))
        patchSelected(["color": .object(color)], label: "Change LUT strength")
    }

    func deleteColorLUT(_ lut: ColorLUT) {
        do {
            try applyThrowing(.deleteColorLUT(id: lut.id), label: "Delete LUT")
        } catch { message = error.localizedDescription }
    }

    private func applyThrowing(_ operation: EditOperation, label: String) throws {
        try commit(operation, label: label)
    }
}
