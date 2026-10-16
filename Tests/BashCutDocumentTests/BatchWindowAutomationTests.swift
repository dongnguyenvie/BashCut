import BashCutDocument
import BashCutProject
import Foundation
import Testing

/// The batch window driven through `ui respond --dialog sheet:batch` (#658), and its messages in the user's language.
struct BatchWindowAutomationTests {
    @Test("Every option ID reads back as the option it names")
    func optionIDs() {
        let options: [BatchWindowOption] = [
            .addInputs, .savePreset, .run, .cancel, .close, .addStep("captions.replace"), .addStep("export"),
            .removeStep(2), .moveStep(1, up: false), .moveStep(3, up: true), .loadPreset("Wave2 rename"),
            .openItem(1), .revealItem(12),
        ]
        for option in options { #expect(BatchWindowOption(option.id) == option, "\(option.id)") }
        #expect(BatchWindowOption("add-step:captions.replace") == .addStep("captions.replace"))
        #expect(BatchWindowOption("move-step-2-up") == .moveStep(2, up: true))
        #expect(BatchWindowOption("load-preset:Wave2 rename") == .loadPreset("Wave2 rename"))
        for bad in ["add-step:", "remove-step-0", "remove-step-x", "move-step-2", "move-step-2-left", "open-0", "load-preset:", "nope"] {
            #expect(BatchWindowOption(bad) == nil, "\(bad)")
        }
    }

    @Test("Editing options: every catalog step, Remove and Move per step within the ends, Load per preset")
    func editingOptions() {
        let ids = BatchWindowOption.editing(steps: 3, presets: ["Wave2 rename"]).map(\.id)
        #expect(Array(ids.prefix(BatchStepCatalog.entries.count)) == BatchStepCatalog.entries.map { "add-step:" + $0.action })
        #expect(Array(ids.dropFirst(BatchStepCatalog.entries.count)) == [
            "remove-step-1", "move-step-1-down",
            "remove-step-2", "move-step-2-up", "move-step-2-down",
            "remove-step-3", "move-step-3-up",
            "load-preset:Wave2 rename",
        ])
        #expect(BatchWindowOption.editing(steps: 0, presets: []).count == BatchStepCatalog.entries.count)
    }

    @Test("A message worded through BatchMessages matches its own key back, with its parts")
    func wordedMessagesMatchBack() throws {
        let missing = BatchMessages.text(BatchMessages.inputMissing, "/tmp/a b.mov")
        #expect(missing == "Input /tmp/a b.mov does not exist")
        #expect(BatchMessage.match(missing)?.key == BatchMessages.inputMissing)
        let step = BatchMessages.step(BatchMessages.exportUnknownPreset, 1, "export", "nope")
        #expect(step == "Step 2 (export): unknown export preset nope")
        let matched = try #require(BatchMessage.match(step))
        #expect(matched.key == BatchMessages.exportUnknownPreset)
        #expect(matched.arguments == ["2", "export", "nope"])
        #expect(Set(BatchMessages.all).count == BatchMessages.all.count)
    }

    @Test("The batch's messages match their patterns, specific ones before the generic step failure")
    func messagePatterns() throws {
        #expect(BatchMessage.match("Give at least one step")?.key == "Give at least one step")
        let notFolder = try #require(BatchMessage.match("Input /tmp/a b is not a folder"))
        #expect(notFolder.key == "Input %@ is not a folder" && notFolder.arguments == ["/tmp/a b"])
        let export = try #require(BatchMessage.match("Step 2 (export): unknown export preset nope"))
        #expect(export.key == "Step %@ (%@): unknown export preset %@" && export.arguments == ["2", "export", "nope"])
        let failed = try #require(BatchMessage.match("Step 1 (captions.replace): find is required"))
        #expect(failed.key == "Step %@ (%@): %@" && failed.arguments == ["1", "captions.replace", "find is required"])
        #expect(BatchMessage.match("Something else broke") == nil)
        #expect(BatchMessage.localized("Something else broke") == "Something else broke")
    }

    @Test("A message is translated with its parts, the failure inside a step message too")
    func translates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("batch-strings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let strings = """
            "Step %@ (%@): %@" = "Bước %1$@ (%2$@): %3$@";
            "The job failed" = "Tác vụ bị lỗi";
            """
        try strings.write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let bundle = try #require(Bundle(url: folder))
        #expect(BatchMessage.localized("Step 3 (captions.generate): The job failed", bundle: bundle)
                == "Bước 3 (captions.generate): Tác vụ bị lỗi")
        #expect(BatchMessage.localized("Give at least one step", bundle: bundle) == "Give at least one step")
    }

    @Test("Every batch message and window option has English and Vietnamese in Localizable.xcstrings")
    func catalogued() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("BashCut/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        let keys = BatchMessage.patterns + [
            "Add step: %@", "Remove step %lld", "Move step %lld up", "Move step %lld down", "Load preset %@",
        ] + BatchStepCatalog.entries.map(\.title)
        for key in keys {
            let localizations = strings[key]?["localizations"] as? [String: [String: Any]]
            let vietnamese = (localizations?["vi"]?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(vietnamese?.isEmpty == false, "no Vietnamese for \(key)")
            let blanks = key.components(separatedBy: "%").count
            #expect(vietnamese.map { $0.components(separatedBy: "%").count } == blanks, "\(key) blanks")
        }
    }
}
