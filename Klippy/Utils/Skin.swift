import SwiftUI
import AppKit
import ImageIO

/// Colour tokens for one Klippy appearance. Names match the design mockup
/// (Klippy.dc.html) one-for-one so a value there translates straight across.
struct Skin: Identifiable, Equatable {
    let id: String
    let label: String

    /// Panel background. `nil` when the skin is image-backed.
    let bg: Color?
    /// Wallpaper behind the panel, drawn under a scrim.
    var image: String?
    /// True for the one skin whose picture is a file the user chose, rather than
    /// something shipped in the app.
    var isCustom: Bool = false

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

    var isImageBacked: Bool { image != nil || isCustom }

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

    /// The user's own picture. Its scrim is worked out from the picture itself,
    /// so a bright photo gets a heavier wash and the text stays readable.
    static func custom(scrimTop: Double, scrimBottom: Double) -> Skin {
        var skin = photoSkin(id: "custom", label: "Your image", image: "",
                             bg: 0x101014, scrimTop: scrimTop, scrimBottom: scrimBottom)
        skin.image = nil
        skin.isCustom = true
        return skin
    }

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
        static let customScrimTop = "klippy.ui.customScrimTop"
        static let customScrimBottom = "klippy.ui.customScrimBottom"
        static let customName = "klippy.ui.customName"
    }

    /// The user's chosen picture, once it has been copied inside the app.
    @Published private(set) var customImage: NSImage?
    /// What to call it in Settings, so the swatch is not anonymous.
    @Published private(set) var customName: String?

    /// Kept inside the app's own container. Copying the file rather than
    /// remembering where it came from means the skin still works after the
    /// original is moved, renamed or deleted, and the sandbox never has to ask
    /// for access to it again.
    private static var customImageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("Klippy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("custom-skin.png")
    }

    var hasCustomImage: Bool { customImage != nil }

    /// The user's picture as a skin, rebuilt from the scrim worked out when it
    /// was chosen. `Skin.named` cannot produce this one: the built-in list is
    /// what ships in the app, and asking it for "custom" silently handed back
    /// Dark, so tapping your own picture in Settings switched you to Dark.
    var customSkin: Skin {
        Skin.custom(
            scrimTop: defaults.object(forKey: Key.customScrimTop) as? Double ?? 0.5,
            scrimBottom: defaults.object(forKey: Key.customScrimBottom) as? Double ?? 0.7
        )
    }

    /// Widest the stored picture is allowed to be. The panel is 640 points
    /// across, so 1600 pixels is already more than a Retina screen can show.
    private static let maxEdge: CGFloat = 1600

    /// Copies the picture in, works out how dark the wash over it needs to be,
    /// and switches to it.
    @discardableResult
    func setCustomImage(from url: URL) -> Bool {
        guard let original = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(original as CFData, nil) else { return false }

        // A photo off a phone is four thousand pixels across. Kept at full size
        // it is tens of megabytes written to disk, read back at every launch and
        // decoded to draw a 640 point panel. The dimensions are read from the
        // header here, so an oversized picture is never fully decoded.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let widest = max(properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                         properties[kCGImagePropertyPixelHeight] as? Int ?? 0)

        let png: Data
        if widest > Int(Self.maxEdge),
           let smaller = ClipboardManager.downsizedPNG(from: original, maxEdge: Self.maxEdge) {
            png = smaller
        } else if let asIs = NSBitmapImageRep(data: original)?
                    .representation(using: .png, properties: [:]) {
            png = asIs
        } else {
            return false
        }

        guard let image = NSImage(data: png),
              let rep = NSBitmapImageRep(data: png) else { return false }

        do { try png.write(to: Self.customImageURL) } catch { return false }

        let (top, bottom) = Self.scrim(for: rep)
        defaults.set(top, forKey: Key.customScrimTop)
        defaults.set(bottom, forKey: Key.customScrimBottom)
        defaults.set(url.deletingPathExtension().lastPathComponent, forKey: Key.customName)

        customImage = image
        customName = url.deletingPathExtension().lastPathComponent
        select(Skin.custom(scrimTop: top, scrimBottom: bottom))
        return true
    }

    func clearCustomImage() {
        try? FileManager.default.removeItem(at: Self.customImageURL)
        customImage = nil
        customName = nil
        defaults.removeObject(forKey: Key.customName)
        if skin.isCustom { select(.dark) }
    }

    /// How dark the wash has to be, measured off the picture rather than
    /// guessed. A bright photo needs a heavy wash or the white text on top
    /// disappears into it; a dark one needs almost none.
    private static func scrim(for rep: NSBitmapImageRep) -> (top: Double, bottom: Double) {
        let samples = 24
        var total = 0.0
        var counted = 0.0
        for x in 0..<samples {
            for y in 0..<samples {
                let px = rep.pixelsWide * x / samples
                let py = rep.pixelsHigh * y / samples
                guard let colour = rep.colorAt(x: px, y: py)?
                        .usingColorSpace(.sRGB) else { continue }
                // Rec. 709 luma: green reads far brighter to the eye than blue.
                total += 0.2126 * Double(colour.redComponent)
                       + 0.7152 * Double(colour.greenComponent)
                       + 0.0722 * Double(colour.blueComponent)
                counted += 1
            }
        }
        guard counted > 0 else { return (0.5, 0.7) }
        let luma = total / counted
        // A near-black picture lands at 0.15, a white one at 0.72.
        let top = min(0.72, max(0.15, 0.10 + luma * 0.70))
        return (top, min(0.85, top + 0.16))
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
        let savedID = defaults.string(forKey: Key.skin) ?? Skin.dark.id
        isWide = defaults.bool(forKey: Key.wide)

        let saved = NSImage(contentsOf: Self.customImageURL)
        customImage = saved
        customName = defaults.string(forKey: Key.customName)

        if savedID == "custom", saved != nil {
            skin = Skin.custom(
                scrimTop: defaults.object(forKey: Key.customScrimTop) as? Double ?? 0.5,
                scrimBottom: defaults.object(forKey: Key.customScrimBottom) as? Double ?? 0.7
            )
        } else {
            // Falls back rather than showing an empty panel when the picture
            // has gone missing.
            skin = .named(savedID)
        }

        // The picture is gone. Stop asking for it, so the next launch does not
        // go through this again.
        if savedID == "custom", saved == nil {
            defaults.set(skin.id, forKey: Key.skin)
        }
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
