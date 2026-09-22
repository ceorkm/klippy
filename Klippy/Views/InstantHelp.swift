import SwiftUI

/// A tooltip that appears the moment the pointer arrives.
///
/// `.help()` hands the job to the system tooltip, and macOS decides when that
/// shows: you have to rest on a control for about a second before anything
/// happens. On a panel of small unlabelled circles that is too slow to be any
/// use, because by the time the label appears you have already clicked the
/// button to find out what it does.
struct InstantHelp: ViewModifier {
    let text: String
    /// Which side of the control the label sits on.
    var edge: Edge = .top

    /// Clear air between the control and the label, and between the label and
    /// the panel's own edge.
    private static let gap: CGFloat = 5
    private static let margin: CGFloat = 12

    @Environment(\.skin) private var skin
    @State private var showing = false
    @State private var size: CGSize = .zero
    @State private var anchor: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: AnchorFrame.self, value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(AnchorFrame.self) { anchor = $0 }
            .onHover { showing = $0 }
            // A view that goes away while the pointer is still inside it never
            // gets its exit, so the label would hang there over whatever came
            // next. Switching tabs does exactly that.
            .onDisappear { showing = false }
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if showing { label }
            }
            .animation(.easeOut(duration: 0.07), value: showing)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(skin.hi)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(skin.pop.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(skin.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 5, y: 1)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: LabelSize.self, value: geo.size)
                }
            )
            .onPreferenceChange(LabelSize.self) { size = $0 }
            // Move by the label's OWN height, measured, not by a number that
            // happened to look right once. Aligned to the control's edge the
            // label starts on top of it; shifting it by its own height plus the
            // gap puts its edge exactly `gap` clear of the control.
            .offset(x: horizontalShift,
                    y: edge == .bottom ? size.height + Self.gap : -(size.height + Self.gap))
            // The label must never eat a click meant for the control under it.
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(1000)
    }

    /// Keeps the label inside the panel.
    ///
    /// The label is centred on its control, which is fine until the control is
    /// near an edge: Settings sits 18 points from the right side, so its label
    /// ran past the panel and the rounded corner clipped it. Nudged back by
    /// however far it overhangs, so it stays put and stays readable.
    private var horizontalShift: CGFloat {
        guard size.width > 0, anchor.width > 0 else { return 0 }

        let panel = SkinStore.shared.panelWidth
        let centre = anchor.midX
        let half = size.width / 2

        if centre + half > panel - Self.margin {
            return (panel - Self.margin) - (centre + half)
        }
        if centre - half < Self.margin {
            return Self.margin - (centre - half)
        }
        return 0
    }
}

private struct LabelSize: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct AnchorFrame: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension View {
    /// Shows `text` on hover with no delay, and reads it out to assistive tech.
    func instantHelp(_ text: String, edge: Edge = .top) -> some View {
        modifier(InstantHelp(text: text, edge: edge))
            .accessibilityLabel(text)
    }
}
