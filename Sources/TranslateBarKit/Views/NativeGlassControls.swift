import SwiftUI

/// Keep the control layer in one system glass container. The content layer
/// uses ordinary adaptive surfaces so long passages remain easy to read.
struct NativeGlassControls<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func nativeGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct NativeIconButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 18, height: 20)
        }
        .nativeGlassButtonStyle()
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}
