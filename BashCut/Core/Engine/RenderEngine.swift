import BashCutProject
import Foundation

public protocol RenderEngine: Sendable {
    /// Builds a playable or exportable composition; `purpose` lets the media source pick proxies for preview.
    func build(_ project: Project, root: URL, workspace: URL?, purpose: RenderPurpose) async throws
        -> CompositionSnapshot
    func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt
}

public struct AVFoundationRenderEngine: RenderEngine {
    private let builder: CompositionBuilder
    private let exporter = Exporter()
    /// One builder per engine, so opened assets are cached across preview rebuilds and exports.
    public init(source: any MediaSource = ProxyMediaSource()) {
        builder = CompositionBuilder(source: source)
    }
    public func build(_ project: Project, root: URL, workspace: URL? = nil, purpose: RenderPurpose) async throws
        -> CompositionSnapshot
    {
        try await builder.build(project, root: root, workspace: workspace, purpose: purpose)
    }
    public func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        try await exporter.export(snapshot, to: url, settings: settings, progress: progress)
    }
}
