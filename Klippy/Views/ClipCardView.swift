import SwiftUI
import AppKit

/// One clip in the history list. Rich previews follow the mockup: images fill the
/// card, colours become the card, everything else shows its text. The bottom row
/// is always the source app's real icon, the age, and a right-aligned detail.
struct ClipCardView: View {
    let item: ClipboardItemViewModel
    let isSelected: Bool
    let justCopied: Bool
    /// True while a secret is still hidden. The first click reveals it, the next
    /// copies it like any other clip.
    var isMasked: Bool = false
    /// Set while the row is hovered, so the right-hand detail gets out of the
    /// way of the delete button that appears in the same corner.
    var hidesDetail: Bool = false

    @Environment(\.skin) private var skin

    /// Restored from the old UI, where body text was resizable.
    @AppStorage("klippy.ui.textSize") private var textSize: Double = 13.5

    @State private var linkPreview: NSImage?
    @State private var siteIcon: NSImage?
    @State private var isHovered = false

    private var swatch: Color? {
        guard item.category == .color else { return nil }
        return Color(hexString: item.content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var preview: NSImage? {
        item.nsImage
    }

    /// The link behind a URL clip, when it is one we could actually load.
    private var linkURL: URL? {
        guard item.category.isLink else { return nil }
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    private var showsMedia: Bool { preview != nil || linkPreview != nil }

    private static let mediaHeight: CGFloat = 128

    var body: some View {
        Group {
            if isMasked {
                maskedCard
            } else if showsMedia {
                mediaCard
            } else {
                textCard
            }
        }
        // Fetching happens here, never in the body getter.
        .task(id: item.id) {
            guard let linkURL else { return }
            // Only the long tail reaches the network. A bundled brand mark is
            // already on screen for the domains we ship.
            let needsFetch = linkURL.host.flatMap(SiteIcon.brand(for:)) == nil
            async let preview = LinkPreviewStore.shared.image(for: linkURL)
            async let favicon = needsFetch
                ? LinkPreviewStore.shared.icon(for: linkURL)
                : nil
            linkPreview = await preview
            siteIcon = await favicon
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(swatch ?? skin.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Every card carries its own hairline edge. A preview with a dark
        // background (the GitHub Copilot page, say) is the same black as the
        // panel, so without this the card has no boundary and bleeds into the
        // list while a bright preview looks like a proper card.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? skin.accent : skin.border,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The old row lifted on hover and the rebuild dropped it, which left the
        // list feeling inert under the pointer.
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(skin.hi.opacity(isHovered && !isSelected ? 0.06 : 0))
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    /// Image and link clips: the preview *is* the card. The source icon, age and
    /// detail sit on the picture over a scrim, rather than in a separate band
    /// underneath, which is how the reference app does it.
    private var mediaCard: some View {
        mediaImage
            .frame(maxWidth: .infinity, minHeight: Self.mediaHeight, maxHeight: Self.mediaHeight)
            .clipped()
            .overlay(alignment: .bottom) { mediaCaption }
            // Lifts a dark preview off an equally dark panel from the inside,
            // so the edge reads even where the hairline alone is too subtle.
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var mediaImage: some View {
        if let image = preview ?? linkPreview {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                // One frame, not two: chaining height then width makes the fill
                // resolve before the width is known, which leaves square images
                // floating in the middle of the card.
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, minHeight: Self.mediaHeight, maxHeight: Self.mediaHeight)
        }
    }

    private var mediaCaption: some View {
        VStack(alignment: .leading, spacing: 6) {
            if linkURL != nil {
                Text(item.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 7) {
                sourceTile

                Text(item.relativeTimeString)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 6)

                Text(justCopied ? "Copied" : detail)
                    .font(.system(size: 11.5, weight: justCopied ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(justCopied ? 1 : 0.75))
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 9)
        .padding(.top, 34)
        // A plain two-stop gradient left the icon and timestamp sitting on the
        // busiest part of a screenshot. Ramping earlier and landing darker keeps
        // them readable over any image without flattening the picture.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.30), location: 0.38),
                    .init(color: .black.opacity(0.70), location: 0.70),
                    .init(color: .black.opacity(0.90), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    /// Keys and card numbers are shown as dots until asked for, so the panel can
    /// be open in front of someone without leaking a secret.
    private var maskedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.maskedText)
                .font(.system(size: textSize, design: .monospaced))
                .foregroundStyle(skin.mid)
                .lineLimit(1)
                .truncationMode(.head)

            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(skin.mid)

                Text(item.category == .paymentCard ? "Card hidden · click to reveal"
                                                   : "Secret hidden · click to reveal")
                    .font(.system(size: 11.5))
                    .foregroundStyle(skin.mid)

                Spacer(minLength: 6)

                Text(detail)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(skin.low)
                    .opacity(hidesDetail ? 0 : 1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bodyText)
                .font(.system(size: swatch == nil ? textSize : textSize + 1.5,
                              weight: swatch == nil ? .regular : .semibold,
                              design: item.category == .code ? .monospaced : .default))
                .foregroundStyle(swatch == nil ? skin.hi : .white)
                .lineSpacing(2)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            footer
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private var bodyText: String {
        item.isMergedClip ? item.mergedComponents.joined(separator: "\n") : item.displayText
    }

    /// A link shows the site it points at, not the browser it was copied from.
    /// TikTok, Reddit, YouTube and everything else resolve automatically because
    /// the icon comes from the domain itself.
    @ViewBuilder
    private var sourceTile: some View {
        if let brand = linkURL?.host.flatMap(SiteIcon.brand(for:)) {
            SiteIconTile(brand: brand)
                .help(linkURL?.host ?? "")
        } else if let siteIcon {
            Image(nsImage: siteIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help(linkURL?.host ?? "")
        } else {
            AppIconTile(bundleID: item.sourceBundleIdentifier, appName: item.sourceApplication)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            sourceTile

            Text(item.relativeTimeString)
                .font(.system(size: 11.5))
                .foregroundStyle(swatch == nil ? skin.mid : Color.white.opacity(0.85))

            Spacer(minLength: 6)

            Text(justCopied ? "Copied" : detail)
                .font(.system(size: 11.5, weight: justCopied ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(detailColor)
                .opacity(hidesDetail && !justCopied ? 0 : 1)
        }
    }

    private var detailColor: Color {
        if justCopied { return swatch == nil ? skin.hi : .white }
        return swatch == nil ? skin.low : Color.white.opacity(0.75)
    }

    /// The right-hand detail: size for images, part count for merged clips,
    /// the colour space for colours, otherwise the time of day.
    private var detail: String {
        if item.isImage { return item.imageSizeString }
        if item.isMergedClip { return "\(item.mergedComponents.count) clips" }
        if swatch != nil { return "HEX" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: item.createdAt)
    }
}

/// Square thumbnail used when the Images filter switches the list into a grid.
struct ClipThumbView: View {
    let item: ClipboardItemViewModel
    let isSelected: Bool
    let justCopied: Bool

    @Environment(\.skin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = item.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    skin.card
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96)
            .clipped()
            // Screenshots are often PNGs with transparent edges. Without a solid
            // tile behind them the skin's wallpaper shows through and every
            // thumbnail looks like a different size.
            .background(skin.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(skin.accent, lineWidth: isSelected ? 2 : 0)
            )

            HStack(spacing: 7) {
                AppIconTile(bundleID: item.sourceBundleIdentifier, appName: item.sourceApplication)

                Text(item.displayText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(skin.hi)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(justCopied ? "Copied" : item.imageSizeString)
                    .font(.system(size: 11.5, weight: justCopied ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(justCopied ? skin.hi : skin.low)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}

extension Color {
    /// Parses `#RGB`, `#RRGGBB` and `#RRGGBBAA`. Returns nil for anything else so
    /// a clip that merely mentions a colour doesn't get painted like one.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()

        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
              let value = UInt32(hex, radix: 16) else { return nil }

        let hasAlpha = hex.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
