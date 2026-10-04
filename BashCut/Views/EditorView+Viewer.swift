import AVKit
import AppKit
import BashCutAutomation
import BashCutDocument
import BashCutProject
import SwiftUI

/// The viewer (program picture, zoom, compare, safe area) and the toolbar format menu.
extension EditorView {
    /// The project size in the toolbar; choosing a canvas changes it as one undoable edit (`project format`).
    var formatMenu: some View {
        Menu {
            ForEach(ProjectSetup.Canvas.allCases, id: \.self) { canvas in
                Button {
                    do { try document.setCanvas(canvas) } catch { document.message = error.localizedDescription }
                } label: {
                    if document.canvas == canvas { Label(canvasTitle(canvas), systemImage: "checkmark") } else {
                        Text(canvasTitle(canvas))
                    }
                }
            }
            Divider()
            ForEach([false, true], id: \.self) { fill in
                Button {
                    do { try document.setClipFill(fill) } catch { document.message = error.localizedDescription }
                } label: {
                    let title: LocalizedStringKey = fill ? "Clips fill the frame" : "Clips fit inside the frame"
                    if document.project.clipsFill == fill { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Text(
                String(
                    format: "%d × %d · %.2f", document.project.width, document.project.height,
                    document.project.fps.value)
            )
            .font(.caption.monospaced())
        }
        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
        .disabled(document.fileURL == nil)
        .help("Change the canvas")
    }
    func canvasTitle(_ canvas: ProjectSetup.Canvas) -> LocalizedStringKey {
        switch canvas {
        case .portrait: "Portrait 9:16"
        case .landscape: "Landscape 16:9"
        case .square: "Square 1:1"
        }
    }
    var viewerZoomMenu: some View {
        Menu {
            ForEach(EditorViewerZoom.choices, id: \.self) { choice in
                Button(choice == "fit" ? String(localized: "Fit") : "\(choice)%") {
                    document.ui.viewerZoom = EditorViewerZoom.scale(choice)
                }
            }
        } label: {
            Text(document.ui.viewerZoom == nil ? String(localized: "Fit") : "\(EditorViewerZoom.choice(document.ui.viewerZoom))%")
                .font(.caption)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(document.project.duration == 0)
        .help("Viewer zoom")
    }
    var viewer: some View {
        VStack(spacing: 0) {
            HStack {
                ViewerModeSwitch(document: document)
                Spacer()
                viewerZoomMenu
                Toggle(
                    "Compare",
                    isOn: Binding(
                        get: { document.preview.showColorComparison },
                        set: { document.preview.setColorComparison($0) })
                ).toggleStyle(.button).font(.caption).disabled(document.project.duration == 0)
                Toggle("Safe area", isOn: Bindable(document.ui).showSafeArea).toggleStyle(.button).font(.caption)
            }.padding(8)
            ZStack {
                Color.black
                if document.project.duration == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.cyan)
                        Text("Start your next cut").font(.headline)
                        if document.fileURL == nil {
                            Button("New project", action: document.newProject)
                            Button("Open project…", action: document.openProject)
                        } else {
                            Button("Import footage…") { document.importMedia() }
                        }
                    }
                } else if let zoom = document.ui.viewerZoom {
                    ScrollView([.horizontal, .vertical]) {
                        viewerFrame.frame(
                            width: Double(document.project.width) * zoom, height: Double(document.project.height) * zoom)
                    }
                } else {
                    // Fit with a margin, so a 16:9 picture does not touch the panel edges. The size is set
                    // explicitly: AVPlayerView fills whatever frame it gets and ignores padding around it.
                    GeometryReader { geometry in
                        let aspect = Double(document.project.width) / Double(max(1, document.project.height))
                        let width = max(1, min(geometry.size.width - 24, (geometry.size.height - 24) * aspect))
                        viewerFrame.frame(width: width, height: width / aspect)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
            TransportBar(document: document)
        }
    }
    /// The program picture with its overlays (compare, safe area), aspect-fit in whatever frame it gets.
    @ViewBuilder var viewerFrame: some View {
        ZStack {
            PlayerView(player: document.preview.player)
            if document.preview.showColorComparison {
                GeometryReader { geometry in
                    PlayerView(player: document.preview.comparisonPlayer)
                        .mask {
                            HStack(spacing: 0) {
                                Rectangle().frame(width: geometry.size.width / 2)
                                Color.clear
                            }
                        }
                    Rectangle().fill(.white.opacity(0.9)).frame(width: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    HStack {
                        Text("Before")
                        Spacer()
                        Text("After")
                    }
                    .font(.caption2.bold()).padding(8)
                    .foregroundStyle(.white).shadow(radius: 2)
                }.allowsHitTesting(false)
            }
            if document.ui.showSafeArea {
                GeometryReader { geo in
                    let aspect = Double(document.project.width) / Double(document.project.height)
                    let height = min(geo.size.height, geo.size.width / aspect)
                    let width = height * aspect
                    Group {
                        if aspect < 1 {
                            // Vertical video: TikTok/Reels cover the bottom and the right edge.
                            ZStack(alignment: .bottomTrailing) {
                                Rectangle().strokeBorder(
                                    .red.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                Rectangle().fill(.red.opacity(0.15)).frame(height: height * 0.16)
                                Rectangle().fill(.red.opacity(0.15)).frame(
                                    width: width * 0.14, height: height * 0.46)
                            }
                        } else {
                            // Landscape and square: keep titles inside the central 90% (title safe).
                            ZStack {
                                Rectangle().strokeBorder(.red.opacity(0.35), lineWidth: 1)
                                Rectangle().strokeBorder(
                                    .red.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5])
                                ).frame(width: width * 0.9, height: height * 0.9)
                            }
                        }
                    }.frame(width: width, height: height).position(
                        x: geo.size.width / 2, y: geo.size.height / 2)
                }.allowsHitTesting(false)
            }
        }
    }
}
