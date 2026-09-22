import SwiftUI
import AppKit
import LinkPresentation
import CryptoKit

/// Fetches the preview image for a copied link so a URL clip shows the page
/// rather than a line of text.
///
/// This is the one part of Klippy that touches the network: it asks the copied
/// site for its own preview image. Nothing is sent anywhere else, nothing is
/// uploaded, and the whole thing is behind a setting that can be switched off.
/// Results are cached on disk so a link is only ever fetched once.
actor LinkPreviewStore {
    static let shared = LinkPreviewStore()

    static let enabledKey = "klippy.preview.links"

    /// Carries an image across an actor boundary on macOS 13.
    ///
    /// `NSImage` only conforms to `Sendable` from macOS 14, and Klippy targets
    /// 13. Unchecked is honest here: every image in this store is decoded once,
    /// never mutated afterwards, and only read from the main actor.
    struct Sent: @unchecked Sendable {
        let image: NSImage?
    }

    private var memory: [String: NSImage] = [:]
    private var icons: [String: NSImage] = [:]
    private var iconMisses: Set<String> = []
    private var iconTasks: [String: Task<Sent, Never>] = [:]
    private var failed: Set<String> = []
    private var running: [String: Task<Sent, Never>] = [:]

    private let cacheDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = base
            .appendingPathComponent("Klippy", isDirectory: true)
            .appendingPathComponent("LinkPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Cached image if we have one, otherwise fetches it once.
    func image(for url: URL) async -> NSImage? {
        guard Self.isEnabled, Self.isSafeToLoad(url) else { return nil }

        let key = Self.key(for: url)
        if let cached = memory[key] { return cached }
        if failed.contains(key) { return nil }

        if let onDisk = loadFromDisk(key) {
            memory[key] = onDisk
            return onDisk
        }

        // Coalesce: the same link can appear in several visible rows at once.
        if let existing = running[key] { return await existing.value.image }

        let task = Task<Sent, Never> { Sent(image: await Self.fetchPreview(for: url)) }
        running[key] = task
        let image = await task.value.image
        running[key] = nil

        // The setting can change while the fetch is in flight.
        guard Self.isEnabled else { return nil }

        if let image {
            memory[key] = image
            writeToDisk(image, key: key)
        } else {
            failed.insert(key)
        }
        return image
    }

    /// A preview means actually loading the page, and some links act the
    /// moment they are opened: a password reset, a magic sign-in, an
    /// unsubscribe. Those are single-use, so fetching one to draw a thumbnail
    /// burns it before the user ever pastes it.
    ///
    /// This looks for the shape of such a link, not for a query string. The
    /// first version refused anything with a "?" or a "#" in it, which is most
    /// of the web: a YouTube video, a Google search, a Hacker News item and an
    /// Amazon product all carry a query, and all of them lost their preview.
    /// Half of a sample of twelve everyday links was blocked. What actually
    /// marks a single-use link is an account-action word in the path, a
    /// credential named in the query or fragment, or one long unbroken token
    /// in the path. The icon fetch is unaffected: it only asks the site root.
    nonisolated static func isSafeToLoad(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let segments = url.pathComponents.filter { $0 != "/" }
        if segments.contains(where: { accountActionWords.contains($0.lowercased()) }) { return false }
        if segments.contains(where: isOpaqueToken) { return false }

        // OAuth returns an access token after the hash rather than in the query,
        // so the fragment is read the same way.
        if let query = url.query, carriesCredential(query) { return false }
        if let fragment = url.fragment, carriesCredential(fragment) { return false }

        return true
    }

    /// Path words that mean "this link does something the moment it loads".
    private static let accountActionWords: Set<String> = [
        "reset", "forgot", "verify", "verification", "confirm", "confirmation",
        "activate", "activation", "invite", "invitation", "magic", "magiclink",
        "login", "signin", "sign-in", "logout", "signout", "auth", "oauth",
        "oauth2", "sso", "token", "session", "password", "otp", "one-time",
        "unsubscribe", "optout", "opt-out"
    ]

    /// Parameter names that carry a secret. The value is never inspected: the
    /// name alone is enough, and reading values would mean logging them.
    private static let credentialKeys: Set<String> = [
        "token", "access_token", "id_token", "refresh_token", "oauth_token",
        "auth", "authorization", "code", "key", "api_key", "apikey", "secret",
        "password", "passwd", "pwd", "session", "sessionid", "sid", "otp",
        "pin", "magic", "invite", "invitation", "reset", "confirm", "verify",
        "signature", "sig", "jwt", "credential", "ticket", "nonce", "unsubscribe"
    ]

    private static func carriesCredential(_ text: String) -> Bool {
        text.split(whereSeparator: { $0 == "&" || $0 == ";" }).contains { pair in
            let name = pair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            return credentialKeys.contains(name.lowercased())
        }
    }

    /// One long unbroken token, which is what a magic link's path looks like.
    ///
    /// Length alone would catch ordinary content: a blog slug runs well past
    /// thirty characters. Slugs are hyphenated words, tokens are not, so the
    /// separator is what tells them apart. A bare identifier like a Spotify
    /// track (22 characters) stays under the bar and keeps its preview.
    private static func isOpaqueToken(_ segment: String) -> Bool {
        if segment.count == 36, UUID(uuidString: segment) != nil { return true }
        guard segment.count >= 32,
              !segment.contains("-"), !segment.contains("_"),
              segment.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return segment.contains(where: \.isNumber) && segment.contains(where: \.isLetter)
    }

    /// The site's own icon, keyed by host so every page on a domain shares one
    /// fetch and one cache entry.
    ///
    /// Deliberately the real favicon from the real site rather than bundled
    /// brand artwork: it needs no trademarked assets shipped in the app, and it
    /// works for every domain instead of a hand-maintained list that would
    /// always be missing something.
    func icon(for url: URL) async -> NSImage? {
        guard Self.isEnabled, let host = url.host else { return nil }

        if let cached = icons[host] { return cached }
        if iconMisses.contains(host) { return nil }

        if let onDisk = loadFromDisk("icon-" + Self.key(for: host)) {
            icons[host] = onDisk
            return onDisk
        }

        if let running = iconTasks[host] { return await running.value.image }

        // Ask the site root, so every URL on the domain resolves the same icon.
        let root = URL(string: "\(url.scheme ?? "https")://\(host)") ?? url
        let task = Task<Sent, Never> { Sent(image: await Self.fetchIcon(for: root)) }
        iconTasks[host] = task
        let image = await task.value.image
        iconTasks[host] = nil

        if let image {
            icons[host] = image
            writeToDisk(image, key: "icon-" + Self.key(for: host))
        } else {
            iconMisses.insert(host)
        }
        return image
    }

    /// Goes straight at the site for its icon rather than through
    /// LPMetadataProvider, which silently returns no icon for YouTube, Reddit
    /// and TikTok (measured: all three fell back to the browser icon while
    /// plain HTTP to the same hosts served an icon fine).
    ///
    /// Tries the big touch icon first and drops to the small favicon. Every
    /// candidate is validated by actually decoding it, because some sites
    /// answer a missing icon with an HTML page and a 200 instead of a 404.
    private static func fetchIcon(for url: URL) async -> NSImage? {
        guard let host = url.host else { return nil }
        let scheme = url.scheme ?? "https"

        let candidates = [
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png",
            "favicon.ico"
        ].compactMap { URL(string: "\(scheme)://\(host)/\($0)") }

        for candidate in candidates {
            if let image = await download(candidate) { return image }
        }
        return nil
    }

    /// Nil unless the bytes really are an image, so an HTML soft-404 is rejected.
    private static func download(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Some sites answer a bare client with a block page.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              !data.isEmpty,
              let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    // MARK: - Fetching

    private static func fetchPreview(for url: URL) async -> NSImage? {
        let metadata: LPLinkMetadata? = await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 8
            // LPMetadataProvider calls back exactly once, but guard anyway —
            // resuming a continuation twice is a hard crash.
            let resumed = ResumeGuard()
            provider.startFetchingMetadata(for: url) { metadata, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: metadata)
            }
        }

        guard let imageProvider = metadata?.imageProvider else { return nil }

        let sent: Sent = await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()
            imageProvider.loadObject(ofClass: NSImage.self) { object, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: Sent(image: object as? NSImage))
            }
        }
        return sent.image
    }

    /// Makes a completion handler single-shot across threads.
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }

    // MARK: - Disk cache

    private func fileURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }

    private func loadFromDisk(_ key: String) -> NSImage? {
        let url = fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func writeToDisk(_ image: NSImage, key: String) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: fileURL(key))
    }

    private static func key(for url: URL) -> String {
        key(for: url.absoluteString)
    }

    private static func key(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Drops every cached preview. Used when the setting is switched off.
    func clearCache() {
        for task in running.values { task.cancel() }
        for task in iconTasks.values { task.cancel() }
        running.removeAll()
        iconTasks.removeAll()
        memory.removeAll()
        failed.removeAll()
        icons.removeAll()
        iconMisses.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
