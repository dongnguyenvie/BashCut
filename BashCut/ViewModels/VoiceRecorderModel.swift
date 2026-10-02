import AVFoundation
import Foundation
import Observation

@MainActor @Observable final class VoiceRecorderModel: NSObject {
    var recording = false
    var elapsed = 0.0
    var level = 0.0
    var error = ""
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var outputURL: URL?

    func start(projectRoot: URL) async {
        guard !recording else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let allowed: Bool
        if status == .authorized {
            allowed = true
        } else if status == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            allowed = false
        }
        guard allowed else {
            error = String(localized: "Microphone access is required to record voiceover.")
            return
        }
        let directory = projectRoot.appendingPathComponent("voiceover/recordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent("voiceover-" + UUID().uuidString + ".wav")
            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.recorder = recorder
            outputURL = url
            elapsed = 0
            level = 0
            error = ""
            recording = true
            startMetering()
        } catch {
            self.error = error.localizedDescription
            cancel()
        }
    }

    func stop() -> URL? {
        guard recording, let recorder else { return nil }
        let url = outputURL
        recorder.stop()
        finish()
        return url
    }

    func cancel() {
        let url = outputURL
        recorder?.stop()
        finish()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, let recorder = self.recorder, self.recording else { return }
                guard recorder.isRecording else {
                    error = String(localized: "Voiceover recording could not be completed.")
                    finish()
                    return
                }
                recorder.updateMeters()
                elapsed = recorder.currentTime
                level = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
            }
        }
    }

    private func finish() {
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        outputURL = nil
        recording = false
        level = 0
    }
}
