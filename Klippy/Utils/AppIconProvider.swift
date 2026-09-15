import SwiftUI
import AppKit

/// Resolves the real macOS icon for the app a clip was copied from.
///
/// There is no stand-in artwork here. Either we find the app's genuine icon or we
/// draw nothing, so a wrong or generic glyph never reaches the UI.
///
/// Resolution order, cheapest and most trustworthy first:
///   1. the bundle identifier recorded with the clip
///   2. the app if it is running right now, using its live bundle URL
///   3. `<Name>.app` in the usual application folders
///
/// Every step is in-process and non-blocking, because this runs during layout.
///
/// Launch Services happily hands back stale paths (a renamed `Cursor.app.bak`, for
/// example) whose icon is the blank generic bundle. Those are rejected explicitly.
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var misses: [String: Date] = [:]
    private let lock = NSLock()
    /// How long a failed lookup stays a miss before we try again.
    /// Short enough that a newly installed app gains its icon soon.
    /// Long enough that a truly missing app does not cost a lookup per row per draw.
    private let missRetryInterval: TimeInterval = 120
    private let maxMisses = 2048

    private init() {
        cache.countLimit = 512
    }

    /// The source app's icon, or nil when it genuinely cannot be found.
    func icon(bundleID: String?, appName: String?) -> NSImage? {
        let key = (bundleID?.isEmpty == false ? bundleID! : appName ?? "") as NSString
        guard key.length > 0 else { return nil }

        if let cached = cache.object(forKey: key) { return cached }

        lock.lock()
        if let lastMiss = misses[key as String] {
            if Date().timeIntervalSince(lastMiss) < missRetryInterval {
                lock.unlock()
                return nil
            }
            misses.removeValue(forKey: key as String)
        }
        lock.unlock()

        guard let url = resolveURL(bundleID: bundleID, appName: appName),
              let image = realIcon(at: url) else {
            lock.lock()
            misses[key as String] = Date()
            if misses.count > maxMisses {
                let oldest = misses.min(by: { $0.value < $1.value })?.key
                if let oldest { misses.removeValue(forKey: oldest) }
            }
            lock.unlock()
            return nil
        }

        lock.lock()
        misses.removeValue(forKey: key as String)
        lock.unlock()
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Resolution

    private func resolveURL(bundleID: String?, appName: String?) -> URL? {
        if let bundleID, !bundleID.isEmpty, let url = urlForBundleID(bundleID) {
            return url
        }
        guard let appName, !appName.isEmpty else { return nil }

        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == appName
        }), let url = running.bundleURL, isUsable(url) {
            return url
        }

        for directory in Self.applicationDirectories {
            let candidate = directory.appendingPathComponent("\(appName).app")
            if isUsable(candidate) { return candidate }
        }

        // Deliberately no Spotlight lookup here. Shelling out to mdfind and
        // blocking on waitUntilExit() from inside a view body segfaulted the app
        // (EXC_BAD_ACCESS in AppIconTile.body). Every lookup on this path must
        // stay in-process and non-blocking.
        return nil
    }

    /// Every install Launch Services knows about, minus the stale ones.
    private func urlForBundleID(_ bundleID: String) -> URL? {
        var candidates: [URL] = []

        if #available(macOS 12.0, *) {
            candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            candidates = [url]
        }

        // A running copy is proof the path is live, so trust it over the rest.
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }), let url = running.bundleURL {
            candidates.insert(url, at: 0)
        }

        let usable = candidates.filter(isUsable)
        return usable.first { $0.path.hasPrefix("/Applications") } ?? usable.first
    }

    /// Rejects paths that don't exist and backup copies, whose icons are blank.
    private func isUsable(_ url: URL) -> Bool {
        guard url.pathExtension == "app",
              FileManager.default.fileExists(atPath: url.path) else { return false }
        let name = url.lastPathComponent.lowercased()
        return !name.hasSuffix(".bak.app") && !name.contains(".app.bak")
    }

    // MARK: - Genuine icons only

    /// Returns the bundle's icon unless macOS handed back the blank generic one.
    private func realIcon(at url: URL) -> NSImage? {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        guard !isGeneric(image) else { return nil }
        return image
    }

    private func isGeneric(_ image: NSImage) -> Bool {
        guard let generic = Self.genericBundleIcon else { return false }
        return fingerprint(image) == generic
    }

    /// Small raster hash, enough to tell "the blank app icon" from a real one.
    private func fingerprint(_ image: NSImage) -> Data? {
        let size = NSSize(width: 32, height: 32)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        guard let tiff = scaled.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static let genericBundleIcon: Data? = {
        let generic = NSWorkspace.shared.icon(for: .applicationBundle)
        return AppIconProvider.shared.fingerprint(generic)
    }()

    private static let applicationDirectories: [URL] = {
        var directories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]
        directories.append(URL(fileURLWithPath: NSHomeDirectory() + "/Applications"))
        return directories
    }()
}

/// The small app-icon tile on every clip. Shows the source app's real icon, or
/// nothing at all — there is deliberately no placeholder artwork.
struct AppIconTile: View {
    let bundleID: String?
    let appName: String?
    var size: CGFloat = 18

    var body: some View {
        if let icon = AppIconProvider.shared.icon(bundleID: bundleID, appName: appName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .help(appName ?? "")
        }
    }
}
