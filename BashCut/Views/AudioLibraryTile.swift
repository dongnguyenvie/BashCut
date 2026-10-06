import BashCutDocument
import BashCutProject
import SwiftUI

/// One audio library item in the Audio panel (#78): play/stop, its name and badges (use, length, BPM, loudness,
/// loop) and Place. Mood and genre are its tags.
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
                LibraryView.title(item).lineLimit(1)
                LibraryAudioBadges(audio: audio, tags: item.tags)
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

    var body: some View {
        HStack(spacing: 4) {
            if let role = audio?.role { badge(Text(Self.roleTitle(role))) }
            if let seconds = audio?.seconds { badge(Text(verbatim: Self.length(seconds))) }
            if let bpm = audio?.bpm { badge(Text(verbatim: "\(Int(bpm.rounded())) BPM")) }
            if let lufs = audio?.lufs { badge(Text(verbatim: String(format: "%.0f LUFS", lufs))) }
            if audio?.loopable == true {
                Image(systemName: "repeat").help("Loops seamlessly")
            }
            if let mood = tags.first { Text(verbatim: mood).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
    }

    private func badge(_ text: Text) -> some View {
        text.padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
    }

    static func roleTitle(_ role: String) -> LocalizedStringKey {
        switch role {
        case "sfx": "SFX"
        case "ambience": "Ambience"
        default: "Music"
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
