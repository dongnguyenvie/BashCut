import AVFoundation
import BashCutAutomation
import BashCutEngine
import BashCutPlugins
import BashCutStorage
import Foundation
import Observation

/// The Voice panel's "Clone a voice" sheet (#532): a source, the window BashCut picked with its checks, a preview,
/// the user's consent, a name, then Save to My voices.
@MainActor @Observable
final class VoiceCloneDraft {
    var name = ""
    var consent = false
    var statement: VoiceConsentStatement = .own
    var sourceTitle = ""
    var prepared: PreparedVoiceClone?
    /// What failed on a refused source (the reason is in `message`).
    var refusedChecks: [String] = []
    var message = ""
    var working = false
    let recorder = VoiceRecorderModel()
    @ObservationIgnored private var recording: URL?
    @ObservationIgnored private var previewTake: [GeneratedVoiceTake] = []
    @ObservationIgnored private let player = AVPlayer()

    var canSave: Bool {
        prepared != nil && consent && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
    }

    func reset() {
        player.pause()
        CapabilityService.discardVoiceTakes(previewTake)
        previewTake = []
        recorder.cancel()
        discardRecording()
        if let prepared { try? FileManager.default.removeItem(at: prepared.trim.output.deletingLastPathComponent()) }
        (name, consent, statement, sourceTitle, prepared, refusedChecks, message, working) =
            ("", false, .own, "", nil, [], "", false)
    }

    /// Trims and checks `source`; the result or the refusal shows in the sheet.
    func analyze(_ source: VoiceCloneSource, title: String, document: ProjectDocument) {
        player.pause()
        if let prepared { try? FileManager.default.removeItem(at: prepared.trim.output.deletingLastPathComponent()) }
        (sourceTitle, prepared, refusedChecks, message, working) = (title, nil, [], "", true)
        Task {
            defer { working = false }
            do {
                prepared = try await document.prepareVoiceClone(source, provider: nil, language: nil)
            } catch let failure as RPCFailure {
                message = failure.message
                refusedChecks = (failure.data?.object["checks"]?.array ?? []).compactMap { check in
                    check.object["passed"] == .bool(false) ? check.object["detail"]?.string : nil
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// The first selected clip that plays sound, as its source seconds.
    func useSelectedClip(_ document: ProjectDocument) {
        guard let item = document.selectedItems.first(where: { $0.mediaID != nil }), let mediaID = item.mediaID,
            let media = document.project.media.first(where: { $0.id == mediaID })
        else {
            message = String(localized: "Select a clip with the voice on the timeline first")
            return
        }
        let span = document.project.sourceSpan(of: item, media: media)
        do {
            let source = try document.cloneSource(mediaID, at: span.lowerBound, to: span.upperBound)
            analyze(source, title: source.description, document: document)
        } catch { message = error.localizedDescription }
    }

    func useFile(_ url: URL, document: ProjectDocument) {
        analyze(VoiceCloneSource(url: url, range: nil, description: url.lastPathComponent), title: url.lastPathComponent,
                document: document)
    }

    func toggleRecording(_ document: ProjectDocument) {
        guard let root = document.fileURL?.deletingLastPathComponent() else { return }
        if recorder.recording {
            guard let url = recorder.stop() else { return }
            discardRecording()
            recording = url
            analyze(VoiceCloneSource(url: url, range: nil, description: "recording"),
                    title: String(localized: "Recording"), document: document)
        } else {
            Task { await recorder.start(projectRoot: root) }
        }
    }

    /// Says a test sentence with the unsaved clone and plays it.
    func preview(_ document: ProjectDocument) {
        guard let prepared, let root = document.fileURL?.deletingLastPathComponent() else { return }
        player.pause()
        CapabilityService.discardVoiceTakes(previewTake)
        working = true
        let reference = VoiceCloneReference(
            path: prepared.trim.output.path, voice: "clone-preview", name: name, language: prepared.language)
        let base = ProjectDocument.baseLanguage(prepared.language)
        let text = base == "vi" ? "Xin chào, đây là giọng nói của tôi được tạo trong BashCut."
            : "Hello, this is my voice, made in BashCut."
        Task {
            defer { working = false }
            do {
                previewTake = try await document.plugins.running("voice.synthesize") {
                    try await document.plugins.service.synthesizeVoiceTakes(
                        text: text, language: prepared.language.isEmpty ? base : prepared.language, count: 1,
                        preferredProvider: prepared.providers.first, projectRoot: root,
                        outputRoot: prepared.trim.output.deletingLastPathComponent().appendingPathComponent("preview"),
                        cloneConsent: true, voice: .clone(reference))
                }
                guard let take = previewTake.first else { return }
                player.replaceCurrentItem(with: AVPlayerItem(url: take.asset.url))
                player.play()
            } catch { message = error.localizedDescription }
        }
    }

    /// Saves to My voices and makes it the project's voice; the sheet closes.
    func save(_ document: ProjectDocument) -> Bool {
        guard canSave, let prepared else { return false }
        do {
            let clone = try document.saveVoiceClone(prepared, name: name, statement: statement, by: "user")
            self.prepared = nil
            _ = try document.useVoice(clone.id, author: .user)
            document.message = String(format: String(localized: "Saved voice %@"), clone.name)
            reset()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func discardRecording() {
        if let recording { try? FileManager.default.removeItem(at: recording) }
        recording = nil
    }
}
