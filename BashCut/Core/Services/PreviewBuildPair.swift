import BashCutEngine
import BashCutProject
import Foundation

struct ComparisonBuildCache: Sendable {
    let project: Project
    let root: URL
    let workspace: URL?
    let programStructure: Int?
    let snapshot: CompositionSnapshot
}

/// Reuse only when both ungraded drawing inputs and the freshly built media structure still match.
/// A text/transform edit can preserve track structure while changing the comparison picture.
struct PreviewBuildPair: Sendable {
    let program: CompositionSnapshot
    let comparison: CompositionSnapshot?
    let cache: ComparisonBuildCache?
    let reusedComparison: Bool

    static func build(
        engine: any RenderEngine, project: Project, location: (root: URL, workspace: URL?), compare: Bool,
        cached: ComparisonBuildCache?
    ) async throws -> PreviewBuildPair {
        let (root, workspace) = location
        guard compare else {
            return try await PreviewBuildPair(
                program: engine.build(project, root: root, workspace: workspace, purpose: .preview),
                comparison: nil, cache: cached, reusedComparison: false)
        }
        var normalized = project.withoutColorEffects()
        normalized.revision = 0
        let ungraded = normalized
        let candidate = cached.flatMap { $0.project == ungraded && $0.root == root && $0.workspace == workspace ? $0 : nil }
        let program: CompositionSnapshot, comparison: CompositionSnapshot
        let reused: Bool
        if let candidate {
            program = try await engine.build(project, root: root, workspace: workspace, purpose: .preview)
            try Task.checkCancellation()
            if let structure = candidate.programStructure, program.structure == structure {
                comparison = candidate.snapshot
                reused = true
            } else {
                // A new proxy, replacement source or changed file can alter structure without a project edit.
                comparison = try await engine.build(ungraded, root: root, workspace: workspace, purpose: .preview)
                reused = false
            }
        } else {
            async let graded = engine.build(project, root: root, workspace: workspace, purpose: .preview)
            async let original = engine.build(ungraded, root: root, workspace: workspace, purpose: .preview)
            (program, comparison) = try await (graded, original)
            reused = false
        }
        try Task.checkCancellation()
        return PreviewBuildPair(program: program, comparison: comparison,
            cache: ComparisonBuildCache(project: ungraded, root: root, workspace: workspace,
                                        programStructure: program.structure, snapshot: comparison), reusedComparison: reused)
    }
}
