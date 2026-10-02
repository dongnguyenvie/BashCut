import AppKit
import BashCutProject
import BashCutStorage

extension ProjectDocument {
    func startExternalFileMonitor() {
        fileMonitor?.cancel()
        guard let fileURL else {
            fileMonitor = nil
            return
        }
        let session = sessionID
        do {
            fileMonitor = try ProjectFileMonitor(fileURL: fileURL) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == session else { return }
                    await self.checkExternalFile()
                }
            }
        } catch {
            fileMonitor = nil
        }
    }

    func save() {
        guard let fileURL, !saving, !conflict else { return }
        let value = history
        let baseline = diskData
        let session = sessionID
        saving = true
        Task {
            defer { saving = false }
            do {
                let written = try await storage.save(value, to: fileURL, expectedDisk: baseline)
                guard session == sessionID else { return }
                diskData = written
                if project == value.project { dirty = false }
                message = String(localized: "Project saved")
            } catch is StorageError {
                guard session == sessionID else { return }
                conflict = true
                message = String(localized: "The project changed on disk")
                await captureExternalProject(fileURL, session: session)
            } catch { message = error.localizedDescription }
        }
    }

    func autosave() {
        guard let fileURL, let diskData, dirty, !saving,
            lastAutosaveRevision != project.revision
        else { return }
        let value = history
        let session = sessionID
        Task {
            do {
                try await storage.autosave(value, at: fileURL, baseline: diskData)
                if session == sessionID { lastAutosaveRevision = value.project.revision }
            } catch { message = error.localizedDescription }
        }
    }

    func checkExternalFile() async {
        guard let fileURL, let diskData, !saving, !busy, !timelineGestureActive, !fileCheckInProgress, !conflict else { return }
        fileCheckInProgress = true
        defer { fileCheckInProgress = false }
        let session = sessionID
        do {
            let data = try await storage.readData(fileURL)
            guard session == sessionID, data != diskData, data != externalData else { return }
            let project = try Project.decode(data)
            externalData = data
            if dirty {
                externalProject = project
                conflict = true
                message = String(localized: "The project changed on disk")
            } else {
                try history.apply(.restore(project), label: "External change (file)", author: .external)
                self.diskData = data
                externalProject = nil
                dirty = true
                rebuild()
            }
        } catch { message = error.localizedDescription }
    }

    func resolveConflict(loadDisk: Bool) {
        guard let fileURL else { return }
        let session = sessionID
        Task {
            do {
                let current = try await storage.readData(fileURL)
                guard session == sessionID else { return }
                if loadDisk {
                    try history.apply(
                        .restore(Project.decode(current)), label: "External change (file)", author: .external)
                    dirty = true
                    rebuild()
                }
                diskData = current
                externalData = nil
                externalProject = nil
                conflict = false
                showExternalChanges = false
                if !loadDisk { save() }
            } catch { message = error.localizedDescription }
        }
    }

    private func captureExternalProject(_ fileURL: URL, session: UUID) async {
        guard let data = try? await storage.readData(fileURL), session == sessionID,
            let decoded = try? Project.decode(data)
        else { return }
        externalData = data
        externalProject = decoded
    }

    var externalChanges: ProjectChangeSet? {
        externalProject.map { $0.changes(from: project) }
    }
}
