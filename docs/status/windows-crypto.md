# Portable crypto validation (W02-02)

Date: 2026-10-06. This change is pending macOS verification; W02-02 remains open.

All twelve direct CryptoKit imports now use Swift Crypto's `Crypto` product. Package.swift and project.yml
declare the dependency wherever cryptographic APIs are imported. SHA-256, Ed25519, persisted hashes, signature
encodings and cache-key algorithms are unchanged. Swift Crypto 3.15.1 delegates to CryptoKit on Apple platforms.
The license and notice are included in the generated About acknowledgements.

## Windows evidence

Swift 6.4.0, MSVC 19.44 and Windows SDK 10.0.22621 headers/libraries were used on x64 Windows. The extracted
toolchain needs source and build-tool SDK flags plus Swift's header module maps, as described in the Windows
repository's `docs/spikes/W00-03.md`. The native SwiftPM backend was used; its deprecation warning remains.

- `swift build --package-path Packages/BashCutCore --target BashCutProject`: passed, 95.66 seconds.
- The actual BashCutProject fixtures and tests were compiled through an ignored local harness with directory
  junctions, avoiding the package's remaining Darwin-dependent Plugin targets. 140 tests in 25 suites passed.
  This includes the new library hash vectors for empty input, abc and the 1 MiB streaming boundary.
- One test was explicitly skipped: `LibraryTests/zippedPack` invokes macOS `/usr/bin/ditto`. The initial
  unfiltered run executed 141 tests and reported that failure plus a schema byte mismatch. Converting the
  checkout's CRLF schema bytes to their committed LF representation resolved the latter; no schema changed.
- The new Ed25519 compatibility test passed against an isolated build of the actual PluginSignature.swift
  and PluginError declaration. Only its module import was renamed in the local test copy. The OpenSSL-derived
  signature/public-key fixture matched, and a different digest was rejected. This is not a full Plugin build.
- Acknowledgements generation/check and changed-source length/whitespace checks passed. Length checks are
  supplementary and do not substitute for SwiftLint.

The Swift 6.4 resolver kept existing package versions but selected swift-custom-dump's newer test-only
swift-issue-reporting dependency in place of xctest-dynamic-overlay. Both package lockfiles are committed;
the complete dependency graph has not been validated with older compilers.

## Remaining acceptance gates

`scripts/verify.sh build`, `test` and `lint` were attempted in the available WSL environment. Build/test could
not start because Swift is absent there; lint reports SwiftLint is not installed. No macOS executor is
available on this host. The PR must remain draft until actual macOS build/tests and SwiftLint --strict pass.
Windows Plugin/process/filesystem portability and the remaining application modules belong to later tickets.
