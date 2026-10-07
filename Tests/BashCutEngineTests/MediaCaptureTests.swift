@preconcurrency import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BashCutEngine

/// Capture facts for `media.inventory` (P0-A6), on generated files.
struct MediaCaptureTests {
    @Test("ISO 6709 positions and EXIF dates read as the camera wrote them")
    func parsing() {
        let place = MediaCapture.location(iso6709: "+21.0285+105.8542+012.345/")
        #expect(place?.latitude == 21.0285 && place?.longitude == 105.8542 && place?.altitude == 12.345)
        #expect(MediaCapture.location(iso6709: "-33.8688+151.2093/")?.latitude == -33.8688)
        #expect(MediaCapture.location(iso6709: "nowhere") == nil)
        #expect(MediaCapture.exifDate("2026:10:07 12:30:05", offset: "+07:00") == "2026-10-07T12:30:05+07:00")
        #expect(MediaCapture.exifDate("bad", offset: nil) == nil)
        // An Android `©xyz` user-data box: size, tag, 16-bit length, language, text.
        let text = Data("+10.7769+106.7009/".utf8)
        var box = Data([0, 0, 0, UInt8(12 + text.count), 0xA9, 0x78, 0x79, 0x7A, 0, UInt8(text.count), 0x15, 0xC7])
        box.append(text)
        let found = MediaCapture.location(userData: Data(repeating: 7, count: 30) + box)
        #expect(found?.latitude == 10.7769 && found?.longitude == 106.7009)
        #expect(MediaCapture.location(userData: Data([0xA9, 0x78, 0x79, 0x7A, 0, 3])) == nil)
    }

    @Test("A photo gives its time, place (south and west negative), device and turned size")
    func photo() throws {
        let root = try TestFixtures.temporaryDirectory("media-capture")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("photo.jpg")
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:07 08:00:00", kCGImagePropertyExifOffsetTimeOriginal: "+07:00",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.5, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 70.25, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Acme", kCGImagePropertyTIFFModel: "Cam 1"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let facts = MediaCapture.image(url, key: "k")
        #expect(facts.capturedAt == "2026-10-07T08:00:00+07:00")
        #expect(facts.location?.latitude == -33.5 && facts.location?.longitude == -70.25)
        #expect(facts.make == "Acme" && facts.model == "Cam 1")
        #expect(facts.width == 20 && facts.height == 40)
    }

    @Test("A movie gives its shown size; facts are kept by content and read again after a change")
    func movie() async throws {
        let root = try TestFixtures.temporaryDirectory("media-capture")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("clip.mov")
        try await PictureSamplerTests.writeMovie(to: url, frames: 10, shade: { _ in 80 })
        let facts = try await MediaCapture.facts(for: url, isImage: false, projectRoot: root)
        #expect(facts.width == 160 && facts.height == 90)
        #expect(facts.location == nil)
        let stored = ProjectCache.record(MediaCapture.self, .inventory, key: facts.key, projectRoot: root)
        #expect(stored == facts)

        // An iPhone-style file: creation date and position in the QuickTime metadata.
        let tagged = root.appendingPathComponent("tagged.mov")
        let location = AVMutableMetadataItem()
        location.identifier = .quickTimeMetadataLocationISO6709
        location.value = "+21.0285+105.8542+012.345/" as NSString
        let created = AVMutableMetadataItem()
        created.identifier = .quickTimeMetadataCreationDate
        created.value = "2026-10-01T08:30:00+07:00" as NSString
        try await PictureSamplerTests.writeMovie(to: tagged, frames: 5, metadata: [location, created], shade: { _ in 50 })
        let taggedFacts = try await MediaCapture.facts(for: tagged, isImage: false, projectRoot: root)
        #expect(taggedFacts.location?.latitude == 21.0285 && taggedFacts.location?.altitude == 12.345)
        #expect(taggedFacts.capturedAt?.hasPrefix("2026-10-01T08:30:00") == true, "\(taggedFacts.capturedAt ?? "nil")")

        // The memo follows the file: a new file at the same path gets a new key.
        let first = try MediaCapture.key(for: url)
        #expect(try MediaCapture.key(for: url) == first)
        try FileManager.default.removeItem(at: url)
        try await PictureSamplerTests.writeMovie(to: url, frames: 12, shade: { _ in 90 })
        #expect(try MediaCapture.key(for: url) != first)
    }
}
