import AppKit
import BashCutDocument
import BashCutEngine
import BashCutProject

extension ProjectDocument {
    func importColorLUT() {
        guard let root = fileURL?.deletingLastPathComponent() else {
            message = String(localized: "Save the project before importing a LUT")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cube")].compactMap { $0 }
        guard let source = ModalCenter.shared.open(panel, name: "import-lut")?.first else { return }
        do {
            let parsed = try CubeLUT.load(source)
            let id = UUID().uuidString
            let relative = "luts/\(id).cube"
            let destination = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source).write(to: destination, options: [.atomic, .withoutOverwriting])
            do {
                try applyThrowing(
                    .addColorLUT(
                        ColorLUT(
                            id: id, name: source.deletingPathExtension().lastPathComponent,
                            path: relative, size: parsed.dimension)),
                    label: "Import LUT")
                message = String(localized: "LUT imported")
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch { message = error.localizedDescription }
    }

    func applyColorLUT(_ id: String?) {
        guard selected != nil else { return }
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
