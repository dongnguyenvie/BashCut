import BashCutProject
import Foundation

public protocol RenderEngine: Sendable {
    func build(_ project: Project, root: URL, workspace: URL?) async throws -> CompositionSnapshot
    func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt
}

public struct AVFoundationRenderEngine: RenderEngine {
    private let builder = CompositionBuilder()
    private let exporter = Exporter()
    public init() {}
    public func build(_ project: Project, root: URL, workspace: URL? = nil) async throws
        -> CompositionSnapshot
    {
        try await builder.build(project, root: root, workspace: workspace)
    }
    public func export(
        _ snapshot: CompositionSnapshot, to url: URL, settings: ExportSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportReceipt {
        try await exporter.export(snapshot, to: url, settings: settings, progress: progress)
    }
}
