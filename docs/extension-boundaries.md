# Extension boundaries

Keep the project model, frame semantics, EditOperation validation, undo history and timeline ownership in a stable core. Preview and export must use the same rendering graph.

M0 exposes RenderEngine as a Sendable protocol, with AVFoundationRenderEngine as the default implementation. ProjectDocument receives this dependency instead of constructing concrete engine services at call sites.

Provider resolution is capability based. Optional transcription, voice, analysis and interchange implementations can be discovered from project, user and bundled plugin folders. Simple effect, transition and style presets should remain data where possible.

Plugins execute out of process through the versioned protocol in [plugin-api.md](plugin-api.md). The app never loads third-party Swift bundles. Core editing operations and timeline state remain native; feature panels can resolve an optional provider and translate its result into validated `EditOperation` values. Signed remote catalogs, richer permission declarations and feature-panel integrations are still pending.
