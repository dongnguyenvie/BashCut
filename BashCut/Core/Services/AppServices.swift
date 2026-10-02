import BashCutEngine
import Foundation

/// The composition root: services that live as long as the app, created once and handed to the
/// document, which builds its per-project controllers (preview, exports, file sync, editor UI state,
/// jobs) from them. Tests pass their own engine, settings store and automation paths.
@MainActor
public final class AppServices {
    public let engine: any RenderEngine
    public let settings: SettingsModel
    public let automation: AutomationController

    public init(engine: any RenderEngine, settings: SettingsModel, automation: AutomationController) {
        self.engine = engine
        self.settings = settings
        self.automation = automation
    }

    /// The running app: AVFoundation rendering, `UserDefaults.standard` and the shared socket and token file.
    public static func live() -> AppServices {
        AppServices(engine: AVFoundationRenderEngine(), settings: SettingsModel(), automation: AutomationController())
    }
}
