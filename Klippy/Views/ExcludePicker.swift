import SwiftUI

/// Tick what Klippy should never write down.
///
/// One screen rather than a section of the settings scroll, because the useful
/// version of this is a list of every app you have copied from, and a dozen
/// rows of switches buried in a form is a chore to read and worse to use.
struct ExcludePicker: View {
    let onDone: () -> Void

    @Environment(\.skin) private var skin
    @ObservedObject private var exclusions = ExclusionStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Anything ticked here is seen and let go. It is never written down, and it never shows up in your history.")
                        .font(.system(size: 12))
                        .foregroundStyle(skin.low)
                        .fixedSize(horizontal: false, vertical: true)

                    group {
                        ForEach(Array(ExclusionStore.offerable.enumerated()), id: \.element) { index, kind in
                            row(title: kind.displayName,
                                detail: Self.blurb[kind] ?? "",
                                isOn: exclusions.excludes(category: kind),
                                isLast: index == ExclusionStore.offerable.count - 1) {
                                exclusions.setExcluded(!exclusions.excludes(category: kind), kind: kind)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onDone) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(skin.hi)
                    .frame(width: 30, height: 30)
                    .background(skin.chip, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text("Never record")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(skin.hi)

            Spacer(minLength: 8)

            Text(exclusions.summary)
                .font(.system(size: 12))
                .foregroundStyle(skin.low)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder rows: () -> Content) -> some View {
        VStack(spacing: 0) { rows() }
            .background(skin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A tick, not a switch. Switches say "turn this feature on"; a tick says
    /// "this one, and this one", which is what the screen is for.
    private func row(title: String, detail: String,
                     isOn: Bool, isLast: Bool,
                     toggle: @escaping () -> Void) -> some View {
        Button {
            toggle()
            FeedbackManager.playPin()
        } label: {
            HStack(spacing: 11) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(skin.hi)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(skin.low)
                        .lineLimit(1)
                }

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? skin.accent : skin.low)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            // Without this the gaps between the label and the tick are not part
            // of the button, so most of the row stays dead.
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 13)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static let blurb: [ContentCategory: String] = [
        .apiKey: "Tokens and keys",
        .paymentCard: "Card numbers",
        .email: "Email addresses",
        .phone: "Phone numbers",
        .address: "Addresses",
        .ipAddress: "IP addresses",
        .identifier: "Reference numbers",
        .url: "Web links",
        .image: "Pictures",
        .file: "Files",
        .code: "Code"
    ]
}
