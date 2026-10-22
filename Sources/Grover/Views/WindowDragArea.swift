import SwiftUI

/// Transparent backdrop that lets the borderless panel be dragged around by
/// its empty areas (bar background, window padding). Controls drawn on top
/// still get their clicks first. The window itself can't be resized.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}
