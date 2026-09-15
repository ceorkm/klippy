import SwiftUI
import AppKit

/// Colour tokens for one Klippy appearance. Names match the design mockup
/// (Klippy.dc.html) one-for-one so a value there translates straight across.
struct Skin: Identifiable, Equatable {
    let id: String
    let label: String

    /// Panel background. `nil` when the skin is image-backed.
    let bg: Color?
    /// Wallpaper behind the panel, drawn under a scrim.
    let image: String?

    /// Scrim darkness at the top and bottom of an image skin. A photo with a
    /// smooth empty sky needs far less than a busy one, so this is per skin
    /// rather than one hardcoded value for all of them.
    var scrimTop: Double = 0.62
    var scrimBottom: Double = 0.78

    let card: Color
    let chip: Color
    let tile: Color

    /// Primary text.
    let hi: Color
    /// Secondary text.
    let mid: Color
    /// Tertiary text and disabled glyphs.
    let low: Color

    let border: Color
    let line: Color

    /// Fill of a selected control.
    let accent: Color
    /// Text drawn on top of `accent`.
    let ink: Color
    /// Popover background.
    let pop: Color
    /// Selected-row wash.
    let sel: Color

    var isImageBacked: Bool { image != nil }

    /// Drives the colour scheme handed to system controls (switches, text fields)
    /// so they don't render dark-on-dark or light-on-light.
    var isDark: Bool { id != "light" }
}

extension Skin {
    static let dark = Skin(
        id: "dark", label: "Dark",
        bg: Color(hex: 0x000000), image: nil,
        card: Color(hex: 0x141416), chip: Color(hex: 0x1C1C1E), tile: Color(hex: 0x26262A),
        hi: Color(hex: 0xF2F2F7), mid: Color(hex: 0x8E8E93), low: Color(hex: 0x6E6E73),
        border: .white.opacity(0.10), line: .white.opacity(0.09),
        accent: .white, ink: .black, pop: Color(hex: 0x161618), sel: .white.opacity(0.09),
    )

    static let light = Skin(
        id: "light", label: "Light",
        bg: Color(hex: 0xF4F4F7), image: nil,
        card: Color(hex: 0xFFFFFF), chip: Color(hex: 0xFFFFFF), tile: Color(hex: 0xE6E6EC),
        hi: Color(hex: 0x111113), mid: Color(hex: 0x55555D), low: Color(hex: 0x63636B),
        border: .black.opacity(0.10), line: .black.opacity(0.07),
        accent: Color(hex: 0x111113), ink: .white, pop: Color(hex: 0xFFFFFF), sel: .black.opacity(0.06),
    )

    /// Every photo skin uses the same glass: dark translucent cards, white text.
    /// Only the scrim changes, tuned to how bright the photo underneath is.
    /// Giving each one its own palette made them feel like different apps.
    private static func photoSkin(id: String, label: String, image: String,
                                  bg: UInt32,
                                  scrimTop: Double, scrimBottom: Double) -> Skin {
        Skin(
            id: id, label: label,
            bg: Color(hex: bg), image: image,
            scrimTop: scrimTop, scrimBottom: scrimBottom,
            card: Color(hex: 0x0C100C).opacity(0.46),
            chip: Color(hex: 0x0C100C).opacity(0.50),
            tile: .white.opacity(0.34),
            hi: .white, mid: Color(hex: 0xE2E6DF), low: Color(hex: 0xC6CCC2),
            border: .white.opacity(0.26), line: .white.opacity(0.18),
            accent: .white, ink: Color(hex: 0x12180F),
            pop: Color(hex: 0x121810).opacity(0.92),
            sel: .white.opacity(0.20)
        )
    }

    static let meadow   = photoSkin(id: "meadow",   label: "Meadow",   image: "skin-meadow",
                                    bg: 0x2E3B2A, scrimTop: 0.62, scrimBottom: 0.78)
    static let hillside = photoSkin(id: "hillside", label: "Hillside", image: "skin-hillside",
                                    bg: 0x8FB0D2, scrimTop: 0.46, scrimBottom: 0.68)
    static let island   = photoSkin(id: "island",   label: "Island",   image: "skin-island",
                                    bg: 0x0168B9, scrimTop: 0.38, scrimBottom: 0.58)

    static let all: [Skin] = [.dark, .light, .meadow, .hillside, .island]

    static func named(_ id: String) -> Skin {
        all.first { $0.id == id } ?? .dark
    }

}

/// Holds the active skin and panel width. Both persist across launches.
///
/// Plain UserDefaults on purpose. `@AppStorage` is a `DynamicProperty` built for
/// View structs; inside an ObservableObject it neither publishes changes nor
/// reliably reads back, which silently broke skin switching entirely.
final class SkinStore: ObservableObject {
    static let shared = SkinStore()

    private enum Key {
        static let skin = "klippy.ui.skin"
        static let wide = "klippy.ui.wide"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var skin: Skin

    @Published var isWide: Bool {
        didSet { defaults.set(isWide, forKey: Key.wide) }
    }

    /// Panel width in points. Matches the mockup's Compact / Wide segment.
    var panelWidth: CGFloat { isWide ? 640 : 430 }

    func select(_ skin: Skin) {
        self.skin = skin
        defaults.set(skin.id, forKey: Key.skin)
    }

    private init() {
        skin = .named(defaults.string(forKey: Key.skin) ?? Skin.dark.id)
        isWide = defaults.bool(forKey: Key.wide)
    }
}

private struct SkinKey: EnvironmentKey {
    static let defaultValue: Skin = .dark
}

extension EnvironmentValues {
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
