@preconcurrency import AVFoundation
import BashCutProject
import Foundation
import ImageIO

/// When, where and with what a source file was recorded, as the file says (P0-A6): the capture time, the GPS
/// position, the device and the picture size as shown (rotation applied). Read once per file content and kept in
/// `.bashcut/cache/inventory`. A field the file does not carry is nil; nothing is guessed from the file name.
public struct MediaCapture: Codable, Sendable, Equatable {
    public static let version = 1

    public struct Location: Codable, Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double
        public var altitude: Double?
    }

    public var version: Int
    public var key: String
    /// ISO 8601, with the file's own offset when it has one.
    public var capturedAt: String?
    public var location: Location?
    public var make: String?
    public var model: String?
    public var software: String?
    /// Picture size as shown, rotation applied.
    public var width: Int?
    public var height: Int?

    public static func key(for url: URL) throws -> String {
        try ProjectCache.contentKey(for: url, namespace: "media-capture-v\(version)")
    }

    /// The stored facts of `url`, or reads and stores them.
    public static func facts(for url: URL, isImage: Bool, projectRoot: URL) async throws -> MediaCapture {
        let key = try key(for: url)
        if let stored = ProjectCache.record(MediaCapture.self, .inventory, key: key, projectRoot: projectRoot),
            stored.version == version, stored.key == key
        {
            return stored
        }
        let facts = isImage ? image(url, key: key) : try await movie(url, key: key)
        try ProjectCache.store(facts, .inventory, key: key, projectRoot: projectRoot)
        return facts
    }

    static func movie(_ url: URL, key: String) async throws -> MediaCapture {
        let asset = AVURLAsset(url: url)
        var facts = MediaCapture(version: version, key: key)
        let items = try await asset.load(.metadata)
        /// The first of `identifiers` the file carries.
        func string(_ identifiers: AVMetadataIdentifier...) async -> String? {
            for identifier in identifiers {
                guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
                    let text = try? await item.load(.stringValue), !text.isEmpty
                else { continue }
                return text
            }
            return nil
        }
        // A phone's own capture time (with its offset) before the container's creation date.
        if let text = await string(.quickTimeMetadataCreationDate) {
            facts.capturedAt = text
        } else if let created = try await asset.load(.creationDate) {
            if let text = try? await created.load(.stringValue), !text.isEmpty {
                facts.capturedAt = text
            } else if let date = try? await created.load(.dateValue) {
                facts.capturedAt = ISO8601DateFormatter().string(from: date)
            }
        }
        if let text = await string(.quickTimeMetadataLocationISO6709, .quickTimeUserDataLocationISO6709, .commonIdentifierLocation) {
            facts.location = Self.location(iso6709: text)
        }
        if facts.location == nil { facts.location = Self.userDataLocation(url) }
        facts.make = await string(.quickTimeMetadataMake, .commonIdentifierMake)
        facts.model = await string(.quickTimeMetadataModel, .commonIdentifierModel)
        facts.software = await string(.quickTimeMetadataSoftware, .commonIdentifierSoftware)
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            let shown = CGRect(origin: .zero, size: size).applying(transform)
            facts.width = Int(abs(shown.width).rounded())
            facts.height = Int(abs(shown.height).rounded())
        }
        return facts
    }

    static func image(_ url: URL, key: String) -> MediaCapture {
        var facts = MediaCapture(version: version, key: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return facts }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            facts.capturedAt = Self.exifDate(original, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        {
            let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
            facts.location = Location(
                latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude,
                altitude: gps[kCGImagePropertyGPSAltitude] as? Double)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        facts.make = tiff[kCGImagePropertyTIFFMake] as? String
        facts.model = tiff[kCGImagePropertyTIFFModel] as? String
        facts.software = tiff[kCGImagePropertyTIFFSoftware] as? String
        if let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        {
            // EXIF orientations 5–8 turn the picture a quarter.
            let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
            (facts.width, facts.height) = turned ? (height, width) : (width, height)
        }
        return facts
    }

    /// `+21.0285+105.8542+012.345/` (ISO 6709 as cameras write it) as a location.
    static func location(iso6709 text: String) -> Location? {
        let pattern = /^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)?/
        guard let match = text.firstMatch(of: pattern), let latitude = Double(match.1), let longitude = Double(match.2),
            abs(latitude) <= 90, abs(longitude) <= 180
        else { return nil }
        return Location(latitude: latitude, longitude: longitude, altitude: match.3.flatMap { Double($0) })
    }

    /// Android phones and many cameras write the position as a `©xyz` box in the MP4's user data, which
    /// AVFoundation does not list. The movie box sits at the start or the end of the file, so both ends are read.
    static func userDataLocation(_ url: URL) -> Location? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let window = UInt64(8 << 20)
        guard let size = try? handle.seekToEnd() else { return nil }
        var parts: [Data] = []
        if (try? handle.seek(toOffset: 0)) != nil, let head = try? handle.read(upToCount: Int(window)) { parts.append(head) }
        if size > window, (try? handle.seek(toOffset: size - window)) != nil, let tail = try? handle.read(upToCount: Int(window)) {
            parts.append(tail)
        }
        return parts.lazy.compactMap(location(userData:)).first
    }

    /// The first `©xyz` box in `data`: a 16-bit length and language, then ISO 6709 text.
    static func location(userData data: Data) -> Location? {
        let tag = Data([0xA9, 0x78, 0x79, 0x7A])
        var from = data.startIndex
        while let range = data.range(of: tag, in: from..<data.endIndex) {
            from = range.upperBound
            guard data.endIndex - range.upperBound >= 4 else { return nil }
            let length = Int(data[range.upperBound]) << 8 | Int(data[range.upperBound + 1])
            let start = range.upperBound + 4
            guard length > 0, length <= 64, start + length <= data.endIndex,
                let text = String(data: data[start..<start + length], encoding: .utf8),
                let location = location(iso6709: text)
            else { continue }
            return location
        }
        return nil
    }

    /// EXIF `2026:10:07 12:30:05` with an optional `+07:00` offset, as ISO 8601.
    static func exifDate(_ text: String, offset: String?) -> String? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == " " })
        guard parts.count == 6 else { return nil }
        return "\(parts[0])-\(parts[1])-\(parts[2])T\(parts[3]):\(parts[4]):\(parts[5])" + (offset ?? "")
    }
}

extension MediaCapture {
    init(version: Int, key: String) {
        self.init(
            version: version, key: key, capturedAt: nil, location: nil, make: nil, model: nil, software: nil, width: nil,
            height: nil)
    }
}
