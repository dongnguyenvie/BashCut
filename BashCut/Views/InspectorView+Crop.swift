import BashCutProject
import SwiftUI

extension InspectorView {
    /// The visible part of the picture and its rounded corners; each side and the radius can be keyframed.
    @ViewBuilder func cropControls(_ item: Item) -> some View {
        DisclosureGroup("Crop") {
            number("Left", group: "crop", key: "left", defaultValue: 0, range: 0...0.95)
            number("Right", group: "crop", key: "right", defaultValue: 0, range: 0...0.95)
            number("Top", group: "crop", key: "top", defaultValue: 0, range: 0...0.95)
            number("Bottom", group: "crop", key: "bottom", defaultValue: 0, range: 0...0.95)
            number("Corner radius", group: "crop", key: "radius", defaultValue: 0, range: 0...0.5)
            PlayheadKeyframeButton(
                document: document, item: item, title: "Keyframe crop at playhead",
                help: "Keys the crop sides and corner radius here; then change them at another frame"
            ) {
                do { try document.keyframeAll(properties: ItemMotion.cropProperties.keys.sorted()) } catch {
                    document.message = error.localizedDescription
                }
            }
        }
    }
}
