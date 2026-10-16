import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation
import Testing

/// Plugin export steps before a final export (plugin API 12, #634).
@MainActor
@Suite("Export steps")
struct ExportStepRunnerTests {
    /// The project the steps see; a test marks the drafts final as the plugin's own `timeline apply` would.
    @MainActor private final class Box {
        var project: Project
        var exported = 0
        var ended: [String] = []
        init(_ project: Project) { self.project = project }
    }

    nonisolated private static func project(graphics: JSONValue?) throws -> Project {
        var media = Media(fields: [
            "id": .string("m"), "path": .string("g.mov"), "frames": .integer(60), "fps": FrameRate(30, 1).json,
            "kind": .string("video"),
        ])
        if let graphics { media.fields["data"] = .object(["graphics": graphics]) }
        return try Project(name: "Steps", fps: FrameRate(30, 1)).applying(
            .group(label: "Setup", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "v", media: "m", at: 0, duration: 60)),
            ])
        ).project
    }

    nonisolated private static let draft: JSONValue = .object(["name": .string("Flow"), "draft": .bool(true)])

    /// A plugin whose `finalise` step runs `script` (bin/step) when `media.data.graphics.draft` holds.
    private static func plugin(_ script: String) throws -> InstalledPlugin {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-steps-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("bin/step")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let step = PluginExportStepContribution(
            id: "finalise", title: LocalizedText("Finalise"), command: PluginCommand(executable: "bin/step"),
            when: "media.data.graphics.draft")
        let manifest = PluginManifest(
            id: "test.graphics", name: LocalizedText("Graphics"), version: "1.0.0", apiVersion: 12,
            entrypoint: "bin/step", capabilities: ["graphics.render"], contributes: PluginContributions(exportSteps: [step]))
        try manifest.validate()
        return InstalledPlugin(manifest: manifest, directory: directory)
    }

    private func runner(_ box: Box, jobs: JobCenter, finalises: Bool = true) -> ExportStepRunner {
        ExportStepRunner(jobs: jobs, session: { run in
            let end: @MainActor () -> Void = {
                box.ended.append(run.step.id)
                // What the plugin's own `timeline apply` did: every draft is final now.
                if finalises, let graphics = try? Self.project(graphics: .object(["name": .string("Flow")])) {
                    box.project = graphics
                }
            }
            return (["BASHCUT_EXPORT_STEP": run.step.id], end)
        }, project: { box.project })
    }

    private func finish(_ jobs: JobCenter, _ id: String) async throws -> Job {
        _ = try await jobs.wait(id, for: .seconds(90), interval: .milliseconds(20))
        while jobs.job(id)?.isActive == true { try await Task.sleep(for: .milliseconds(20)) }
        return try #require(jobs.job(id))
    }

    @Test("Steps match drafts on the timeline for a final export; quick drafts and media without data.graphics skip")
    func matching() throws {
        let plugin = try Self.plugin("exit 0")
        let drafted = try Self.project(graphics: Self.draft)
        #expect(ExportStepRun.matching([plugin], project: drafted, presets: [.tiktok]).map(\.step.id) == ["finalise"])
        #expect(ExportStepRun.matching([plugin], project: drafted, presets: [.quickDraft, .tiktok]).count == 1)
        #expect(ExportStepRun.matching([plugin], project: drafted, presets: [.quickDraft]).isEmpty)
        #expect(ExportStepRun.matching([plugin], project: try Self.project(graphics: nil), presets: [.tiktok]).isEmpty)
        let final = try Self.project(graphics: .object(["name": .string("Flow"), "draft": .bool(false)]))
        #expect(ExportStepRun.matching([plugin], project: final, presets: [.tiktok]).isEmpty)
        let json = ExportStepRun.matching([plugin], project: drafted, presets: [.tiktok])[0].json(drafted).object
        #expect(json["media"] == .array([.string("m")]) && json["plugin"] == .string("test.graphics"))
    }

    @Test("A matching step runs with progress, the project is read again, then the export starts")
    func runsThenExports() async throws {
        let plugin = try Self.plugin("echo \"::progress 0.5 Rendering Flow\"; test \"$BASHCUT_EXPORT_STEP\" = finalise")
        let box = Box(try Self.project(graphics: Self.draft))
        let jobs = JobCenter()
        let steps = ExportStepRun.matching([plugin], project: box.project, presets: [.tiktok])
        let id = runner(box, jobs: jobs).start(steps, author: .claude) {
            box.exported += 1
            return .array([.string("export-job")])
        }
        let job = try await finish(jobs, id)
        #expect(job.state == .completed && job.method == ExportStepRunner.method)
        #expect(box.exported == 1 && box.ended == ["finalise"])
        #expect(job.result.object["exports"] == .array([.string("export-job")]))
        #expect(job.result.object["steps"]?.array.first?.object["media"] == .array([.string("m")]))
    }

    @Test("Cancelling the step stops it and exports nothing")
    func cancelAborts() async throws {
        let plugin = try Self.plugin("sleep 120")
        let box = Box(try Self.project(graphics: Self.draft))
        let jobs = JobCenter()
        let steps = ExportStepRun.matching([plugin], project: box.project, presets: [.tiktok])
        let started = Date()
        let id = runner(box, jobs: jobs).start(steps, author: .user) {
            box.exported += 1
            return .null
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(jobs.cancel(id))
        let job = try await finish(jobs, id)
        #expect(job.state == .cancelled && box.exported == 0 && box.ended == ["finalise"])
        // Far less than the step's own 120 s, even with every suite running at once.
        #expect(Date().timeIntervalSince(started) < 60)
    }

    @Test("A failing step reports the plugin, the step and its output, and exports nothing")
    func failureReports() async throws {
        let plugin = try Self.plugin("echo 'Chrome headless shell is missing' >&2; exit 3")
        let box = Box(try Self.project(graphics: Self.draft))
        let jobs = JobCenter()
        let steps = ExportStepRun.matching([plugin], project: box.project, presets: [.tiktok])
        let id = runner(box, jobs: jobs).start(steps, author: .claude) {
            box.exported += 1
            return .null
        }
        let job = try await finish(jobs, id)
        #expect(job.state == .failed && box.exported == 0)
        #expect(job.error == "Export step Finalise (Graphics) failed: Chrome headless shell is missing")
    }

    @Test("A step that leaves its condition true fails before exporting")
    func stillMatching() async throws {
        let plugin = try Self.plugin("exit 0")
        let box = Box(try Self.project(graphics: Self.draft))
        let jobs = JobCenter()
        let steps = ExportStepRun.matching([plugin], project: box.project, presets: [.tiktok])
        let id = runner(box, jobs: jobs, finalises: false).start(steps, author: .claude) {
            box.exported += 1
            return .null
        }
        let job = try await finish(jobs, id)
        #expect(job.state == .failed && box.exported == 0)
        #expect(job.error?.contains("still match media.data.graphics.draft: m. Nothing was exported.") == true)
    }
}
