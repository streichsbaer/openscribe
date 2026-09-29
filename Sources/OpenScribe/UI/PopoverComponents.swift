import SwiftUI

private struct InstantHintModifier: ViewModifier {
    let text: String
    @Binding var hoverHint: String?

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { isHovering in
                if isHovering {
                    hoverHint = text
                } else if hoverHint == text {
                    hoverHint = nil
                }
            }
    }
}

extension View {
    func instantHint(_ text: String, hoverHint: Binding<String?>) -> some View {
        modifier(InstantHintModifier(text: text, hoverHint: hoverHint))
    }
}
