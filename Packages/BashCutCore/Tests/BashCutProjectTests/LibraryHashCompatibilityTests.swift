import Foundation
import Testing

@testable import BashCutProject

@Suite("Portable library hashes")
struct LibraryHashCompatibilityTests {
    @Test("Stored hashes retain the SHA-256 empty and abc vectors")
    func standardVectors() throws {
        try check(Data(), digest: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        try check(Data("abc".utf8), digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Stored hashes remain compatible across the one-megabyte streaming boundary")
    func chunkBoundary() throws {
        // Independently calculated with Python hashlib for 1,048,577 ASCII a bytes.
        try check(
            Data(repeating: 0x61, count: (1 << 20) + 1),
            digest: "4a3f0c0c213adea174f9a3d4c13177315b588bdb2e9c1012d3d0bf0453ca0f6a")
    }

    private func check(_ bytes: Data, digest: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hash-vector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        try bytes.write(to: source)
        let store = LibraryStore(root: root.appendingPathComponent("library"), scope: .user)
        let stored = try store.add(LibraryItem(id: "vector", kind: .audio, name: "Vector"), file: source)
        #expect(stored["fileSHA256"]?.string == digest)
        #expect(try LibraryStore.sha256(of: source) == digest)
    }
}
