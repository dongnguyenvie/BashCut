import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import BashCutStorage

extension ProjectDocument {
    var storage: ProjectStorage { fileSync.storage }
    var conflict: Bool { fileSync.conflict }
    var saving: Bool { fileSync.saving }

    func startExternalFileMonitor() {
        guard let fileURL else { return }
        fileSync.watch(fileURL) { [weak self] in
            Task { await self?.checkExternalFile() }
        }
    }

    func save() {
        guard fileURL != nil, !saving, !conflict else { return }
        Task {
            do { try await saveNow() } catch is StorageError {} catch { message = error.localizedDescription }
        }
    }

    /// Saves and waits for the write. A disk conflict marks the document conflicted and throws.
    func saveNow() async throws {
        guard let fileURL else { throw ProjectError.invalid("The project has not been saved to a folder yet") }
        let value = history
        do {
            guard try await fileSync.save(value, to: fileURL) else { return }
            if project == value.project { dirty = false }
            message = String(localized: "Project saved")
            DebugLog.write("project", "saved \(fileURL.path) rev=\(value.project.revision)")
            emitPluginEvent(.projectSaved, ["path": .string(fileURL.path), "rev": .integer(value.project.revision)])
        } catch let error as StorageError {
            message = String(localized: "The project changed on disk")
            DebugLog.write("project", "save CONFLICT \(fileURL.path): file changed on disk")
            throw error
        }
    }

    func autosave() {
        guard let fileURL else { return }
        let value = history
        let isDirty = dirty
        Task {
            do { try await fileSync.autosave(value, at: fileURL, dirty: isDirty) } catch {
                message = error.localizedDescription
            }
        }
    }

    func checkExternalFile() async {
        guard let fileURL, !busy, !timelineGestureActive else { return }
        do {
            switch try await fileSync.checkDisk(fileURL, dirty: dirty) {
            case .unchanged: break
            case .conflict: message = String(localized: "The project changed on disk")
            case .reload(let project, let data):
                try commit(.restore(project), label: "External change (file)", author: .external)
                fileSync.accept(data)
            }
        } catch { message = error.localizedDescription }
    }

    func resolveConflict(loadDisk: Bool) {
        guard let fileURL else { return }
        Task {
            do {
                guard let current = try await fileSync.readDisk(fileURL) else { return }
                if loadDisk {
                    try commit(
                        .restore(Project.decode(current)), label: "External change (file)", author: .external)
                }
                fileSync.resolve(with: current)
                ui.showExternalChanges = false
                if !loadDisk { save() }
            } catch { message = error.localizedDescription }
        }
    }

    var externalChanges: ProjectChangeSet? {
        fileSync.externalProject.map { $0.changes(from: project) }
    }
}
