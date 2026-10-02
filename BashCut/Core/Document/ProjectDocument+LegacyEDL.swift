import AppKit
import BashCutDocument
import BashCutImport
import BashCutProject

extension ProjectDocument {
    func importLegacyEDL() {
        guard !busy, !saving, confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose an edl.json file")
        guard let source = ModalCenter.shared.open(panel, name: "import-edl")?.first else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await importLegacyEDL(from: source)
                showLegacyImportReport = true
            } catch { message = error.localizedDescription }
        }
    }

    /// Converts a legacy edl.json into project.bashcut.json beside it and opens it. The caller handles
    /// unsaved changes of the open project first.
    @discardableResult
    func importLegacyEDL(from source: URL) async throws -> LegacyEDLImportReport {
        let directory = source.deletingLastPathComponent()
        let destination = directory.appendingPathComponent("project.bashcut.json")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ProjectError.invalid(String(localized: "project.bashcut.json already exists beside this EDL"))
        }
        let folder = directory.lastPathComponent == "timeline"
            ? directory.deletingLastPathComponent().lastPathComponent : directory.lastPathComponent
        let data = try await storage.readData(source)
        let report = try LegacyEDLImporter.decode(data, name: folder, destinationDirectory: directory)
        let importedHistory = ProjectHistory(project: report.project)
        let written = try await storage.save(importedHistory, to: destination, expectedDisk: nil)
        reset(report.project, url: destination)
        replaceHistory(importedHistory)
        diskData = written
        legacyImportReport = report
        message = String(localized: "Legacy EDL imported")
        rebuild()
        return report
    }
}
