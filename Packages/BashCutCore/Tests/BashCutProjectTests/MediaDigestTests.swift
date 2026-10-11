import Testing

@testable import BashCutProject

/// `media.digest`: the footage facts of one media in time order, with possible retakes marked.
struct MediaDigestTests {
    let phrases = [
        SubRip.Cue(start: 1.0, end: 3.0, text: "Hôm nay mình đi chợ nổi Cái Răng"),
        SubRip.Cue(start: 4.0, end: 6.0, text: "Hôm nay mình đi chợ nổi Cái Răng nha"),
        SubRip.Cue(start: 7.0, end: 8.0, text: "Ok"),
        SubRip.Cue(start: 300.0, end: 302.0, text: "Hôm nay mình đi chợ nổi Cái Răng"),
    ]

    func shot(_ start: Double, _ end: Double, size: String, note: String) -> MediaDescription.Shot {
        MediaDescription.Shot(
            start: start, end: end, size: size, angle: "eye", move: "handheld", direction: nil, subjects: ["boat"],
            people: nil, onScreenText: nil, confidence: nil, bestMoment: nil, looked: [], note: note)
    }

    @Test("A phrase said again soon after is marked with the later start; one far away or too short is not")
    func retakes() {
        let digest = MediaDigest(
            media: "m", name: "a.mp4", seconds: 400, size: "1920x1080", cuts: [5, 12], shots: [], phrases: phrases,
            speechSeconds: 7)
        #expect(digest.phrases.map(\.againAt) == [4.0, nil, nil, nil])
        // Different lines that share short words are not retakes.
        let lines = MediaDigest(
            media: "m", name: "a.mp4", seconds: 100, size: nil, cuts: nil, shots: [],
            phrases: [
                SubRip.Cue(start: 21, end: 23, text: "cho mình để mình cạo lông anh"),
                SubRip.Cue(start: 84.8, end: 87, text: "để mình cạo lông bây giờ"),
            ], speechSeconds: nil)
        #expect(lines.phrases.allSatisfy { $0.againAt == nil })
    }

    @Test("Text: header, then described shots and phrases in time order and the cuts no shot covers")
    func text() {
        let digest = MediaDigest(
            media: "m", name: "a.mp4", seconds: 400, size: "1920x1080", cuts: [5, 12],
            shots: [shot(0, 10, size: "WS", note: "market")], phrases: Array(phrases.prefix(3)), speechSeconds: 5)
        let lines = digest.text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "media m \"a.mp4\" 400.0s 1920x1080 speech 1% | 3 phrases, 1 described shots, 3 measured shots")
        #expect(lines.contains("cuts 12.0"))
        #expect(lines.contains("shot 0.0-10.0 WS eye handheld | boat | market"))
        #expect(lines.contains("1.0 Hôm nay mình đi chợ nổi Cái Răng [again 4.0]"))
        #expect(lines.firstIndex(of: "7.0 Ok")! > lines.firstIndex(of: "shot 0.0-10.0 WS eye handheld | boat | market")!)
        let part = digest.range(from: 3.5, to: 6.5)
        #expect(part.text.split(separator: "\n").count == 3)
    }
}
