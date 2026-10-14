import BashCutDocument
import BashCutProject
import SwiftUI

/// One audio library item in the Audio panel (#78): play/stop, its name and badges (use, length, BPM, loudness,
/// loop), its waveform and Place. Mood and genre are its tags.
struct AudioLibraryTile: View {
    @Bindable var document: ProjectDocument
    let item: LibraryItem
    private var preview = LibraryAudioPreview.shared

    init(document: ProjectDocument, item: LibraryItem) {
        self.document = document
        self.item = item
    }

    var body: some View {
        let playing = preview.playing == item.reference
        let audio = try? LibraryAudio(params: item.params)
        HStack(spacing: 6) {
            Button {
                document.toggleLibraryPreview(item)
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 14)
            }
            .buttonStyle(.borderless)
            .help(playing ? "Stop" : "Play")
            .accessibilityLabel(playing ? Text("Stop") : Text("Play"))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    LibraryView.title(item).lineLimit(1).help(Text(verbatim: item.name))
                    LibraryItemBadges(item: item, inline: true).fixedSize()
                }
                LibraryAudioBadges(audio: audio, tags: item.tags)
                LibraryWaveformView(url: document.libraryCatalog.fileURL(of: item))
            }
            Spacer(minLength: 4)
            Button("Place") { document.placeFromLibrary(item) }
                .disabled(document.fileURL == nil)
                .help("Place at the playhead on the Music or SFX layer")
        }
        .font(.caption)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(playing ? 0.1 : 0.04)))
    }
}

/// Small facts about a library sound: its use, length, tempo, loudness and whether it loops.
struct LibraryAudioBadges: View {
    let audio: LibraryAudio?
    var tags: [String] = []

    /// Chips stay whole on one line: when the row is too narrow the mood tag goes first, then LUFS, then BPM.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(bpm: true, lufs: true, mood: true)
            row(bpm: true, lufs: true, mood: false)
            row(bpm: true, lufs: false, mood: false)
            row(bpm: false, lufs: false, mood: false)
        }
        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
    }

    private func row(bpm showBPM: Bool, lufs showLUFS: Bool, mood showMood: Bool) -> some View {
        HStack(spacing: 4) {
            if let role = audio?.role { badge(Text(Self.roleTitle(role))) }
            if let seconds = audio?.seconds { badge(Text(verbatim: Self.length(seconds))) }
            if showBPM, let bpm = audio?.bpm { badge(Text(verbatim: "\(Int(bpm.rounded())) BPM")) }
            if showLUFS, let lufs = audio?.lufs { badge(Text(verbatim: String(format: "%.0f LUFS", lufs))) }
            if audio?.loopable == true {
                Image(systemName: "repeat").help("Loops seamlessly")
            }
            if showMood, let mood { Text(verbatim: mood).foregroundStyle(.tertiary).fixedSize() }
        }
    }

    /// The first tag, unless it only repeats the role chip ("sfx" next to SFX).
    private var mood: String? {
        guard let tag = tags.first else { return nil }
        let role = audio?.role ?? ""
        let repeats = [role, Self.roleName(role)].contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        return repeats ? nil : tag
    }

    private func badge(_ text: Text) -> some View {
        text.lineLimit(1).fixedSize().padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
    }

    static func roleTitle(_ role: String) -> LocalizedStringKey {
        switch role {
        case "sfx": "SFX"
        case "ambience": "Ambience"
        default: "Music"
        }
    }

    /// The role as the chip says it, in English lowercase ("music" for any other role).
    static func roleName(_ role: String) -> String {
        switch role {
        case "sfx", "ambience": role
        default: "music"
        }
    }

    static func length(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return seconds < 10 ? String(format: "%.1fs", seconds) : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// One line for the item sheet: length, tempo, loudness and true peak, when measured.
    static func summary(_ audio: LibraryAudio) -> String? {
        var parts: [String] = []
        if let seconds = audio.seconds { parts.append(length(seconds)) }
        if let bpm = audio.bpm { parts.append(String(format: "%.1f BPM", bpm)) }
        if let lufs = audio.lufs { parts.append(String(format: "%.1f LUFS", lufs)) }
        if let peak = audio.truePeak { parts.append(String(format: "%.1f dBTP", peak)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
