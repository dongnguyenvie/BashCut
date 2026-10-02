import AppKit
import BashCutImport
import BashCutProject

extension ProjectDocument {
    func importLegacyEDL() {
        guard !busy, !saving, confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Choose an edl.json file")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let directory = source.deletingLastPathComponent()
        let destination = directory.appendingPathComponent("project.bashcut.json")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            message = String(localized: "project.bashcut.json already exists beside this EDL")
            return
        }
        let folder = directory.lastPathComponent == "timeline"
            ? directory.deletingLastPathComponent().lastPathComponent : directory.lastPathComponent
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await storage.readData(source)
                let report = try LegacyEDLImporter.decode(
                    data, name: folder, destinationDirectory: directory)
                let importedHistory = ProjectHistory(project: report.project)
                let written = try await storage.save(importedHistory, to: destination, expectedDisk: nil)
                reset(report.project, url: destination)
                history = importedHistory
                diskData = written
                legacyImportReport = report
                showLegacyImportReport = true
                message = String(localized: "Legacy EDL imported")
                rebuild()
            } catch { message = error.localizedDescription }
        }
    }
}
