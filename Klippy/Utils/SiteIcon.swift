import SwiftUI

/// The brand icon for a copied link, drawn from artwork bundled in the app.
///
/// Bundled rather than fetched on purpose. A clipboard manager that asks every
/// copied domain for its favicon tells that site you copied its link, which is
/// exactly the kind of leak a clipboard app must not have, and it puts a
/// "browsing data" line on the App Store privacy label. Bundled icons also draw
/// instantly, offline, at full resolution, instead of after a round trip.
///
/// Artwork is Simple Icons (CC0-1.0). Brands that asked Simple Icons to drop
/// their mark are deliberately absent here and fall through to the optional
/// favicon fetch, so no trademark is shipped against its owner's wishes.
enum SiteIcon {
    struct Brand {
        let slug: String
        let hex: UInt32
        init(_ slug: String, _ hex: UInt32) { self.slug = slug; self.hex = hex }
    }

    /// Exact host match wins, then each parent domain, so `m.youtube.com` and
    /// `www.youtube.com` both land on `youtube.com`.
    static func brand(for host: String) -> Brand? {
        var parts = host.lowercased().split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let hit = brands[parts.joined(separator: ".")] { return hit }
            parts.removeFirst()
        }
        return nil
    }

    static let brands: [String: Brand] = [
        "1password.com": Brand("1password", 0x145FE4),
        "airbnb.com": Brand("airbnb", 0xFF5A5F),
        "airtable.com": Brand("airtable", 0x18BFFF),
        "aliexpress.com": Brand("aliexpress", 0xFF4747),
        "angular.io": Brand("angular", 0x0F0F11),
        "anthropic.com": Brand("anthropic", 0x191919),
        "apple.com": Brand("apple", 0x000000),
        "apps.apple.com": Brand("appstore", 0x0D96F6),
        "archive.org": Brand("internetarchive", 0x666666),
        "archlinux.org": Brand("archlinux", 0x1793D1),
        "arstechnica.com": Brand("arstechnica", 0xFF4E00),
        "artstation.com": Brand("artstation", 0x13AFF0),
        "asana.com": Brand("asana", 0xF06A6A),
        "atlassian.net": Brand("jira", 0x0052CC),
        "bandcamp.com": Brand("bandcamp", 0x408294),
        "basecamp.com": Brand("basecamp", 0x1D2D35),
        "behance.net": Brand("behance", 0x1769FF),
        "bereal.com": Brand("bereal", 0x000000),
        "binance.com": Brand("binance", 0xF0B90B),
        "bitbucket.org": Brand("bitbucket", 0x0052CC),
        "bitwarden.com": Brand("bitwarden", 0x175DDC),
        "booking.com": Brand("bookingdotcom", 0x003A9A),
        "box.com": Brand("box", 0x0061D5),
        "brew.sh": Brand("homebrew", 0xFBB040),
        "bsky.app": Brand("bluesky", 0x1185FE),
        "calendar.google.com": Brand("googlecalendar", 0x4285F4),
        "calendly.com": Brand("calendly", 0x006BFF),
        "cash.app": Brand("cashapp", 0x00C244),
        "claude.ai": Brand("claude", 0xD97757),
        "clickup.com": Brand("clickup", 0x7B68EE),
        "cloudflare.com": Brand("cloudflare", 0xF38020),
        "clubhouse.com": Brand("clubhouse", 0xFFE450),
        "cnn.com": Brand("cnn", 0xCC0000),
        "codeberg.org": Brand("codeberg", 0x2185D0),
        "codecademy.com": Brand("codecademy", 0x1F4056),
        "codesandbox.io": Brand("codesandbox", 0x151515),
        "coinbase.com": Brand("coinbase", 0x0052FF),
        "confluence.atlassian.com": Brand("confluence", 0x172B4D),
        "coursera.org": Brand("coursera", 0x0056D2),
        "crates.io": Brand("rust", 0x000000),
        "cursor.com": Brand("cursor", 0x000000),
        "dailymotion.com": Brand("dailymotion", 0x0A0A0A),
        "datadoghq.com": Brand("datadog", 0x632CA6),
        "deezer.com": Brand("deezer", 0xA238FF),
        "dev.to": Brand("devdotto", 0x0A0A0A),
        "developer.apple.com": Brand("apple", 0x000000),
        "developer.mozilla.org": Brand("mdnwebdocs", 0x000000),
        "deviantart.com": Brand("deviantart", 0x05CC47),
        "digitalocean.com": Brand("digitalocean", 0x0080FF),
        "discord.com": Brand("discord", 0x5865F2),
        "discord.gg": Brand("discord", 0x5865F2),
        "docker.com": Brand("docker", 0x2496ED),
        "docs.google.com": Brand("googledocs", 0x4285F4),
        "doordash.com": Brand("doordash", 0xFF3008),
        "douyin.com": Brand("tiktok", 0x000000),
        "dribbble.com": Brand("dribbble", 0xEA4C89),
        "drive.google.com": Brand("googledrive", 0x4285F4),
        "dropbox.com": Brand("dropbox", 0x0061FF),
        "duolingo.com": Brand("duolingo", 0x58CC02),
        "ebay.com": Brand("ebay", 0xE53238),
        "epicgames.com": Brand("epicgames", 0x313131),
        "etsy.com": Brand("etsy", 0xF16521),
        "evernote.com": Brand("evernote", 0x00A82D),
        "facebook.com": Brand("facebook", 0x0866FF),
        "fb.com": Brand("facebook", 0x0866FF),
        "figma.com": Brand("figma", 0xF24E1E),
        "firebase.google.com": Brand("firebase", 0xDD2C00),
        "fiverr.com": Brand("fiverr", 0x1DBF73),
        "flickr.com": Brand("flickr", 0x0063DC),
        "fly.io": Brand("flydotio", 0x24175B),
        "freecodecamp.org": Brand("freecodecamp", 0x0A0A23),
        "gemini.google.com": Brand("googlegemini", 0x8E75B2),
        "giphy.com": Brand("giphy", 0xFF6666),
        "gist.github.com": Brand("github", 0x181717),
        "github.com": Brand("github", 0x181717),
        "gitlab.com": Brand("gitlab", 0xFC6D26),
        "glassdoor.com": Brand("glassdoor", 0x00A162),
        "go.dev": Brand("go", 0x00ADD8),
        "goodreads.com": Brand("goodreads", 0x1E1914),
        "google.com": Brand("google", 0x4285F4),
        "grafana.com": Brand("grafana", 0xF46800),
        "gumroad.com": Brand("gumroad", 0xFF90E8),
        "hackerrank.com": Brand("hackerrank", 0x00EA64),
        "hashnode.com": Brand("hashnode", 0x2962FF),
        "hbomax.com": Brand("hbo", 0x000000),
        "hub.docker.com": Brand("docker", 0x2496ED),
        "hubspot.com": Brand("hubspot", 0xFF7A59),
        "huggingface.co": Brand("huggingface", 0xFFD21E),
        "icloud.com": Brand("icloud", 0x3693F3),
        "imdb.com": Brand("imdb", 0xF5C518),
        "imgur.com": Brand("imgur", 0x1BB76E),
        "indeed.com": Brand("indeed", 0x003A9B),
        "instagram.com": Brand("instagram", 0xFF0069),
        "intercom.com": Brand("intercom", 0x6AFDEF),
        "itch.io": Brand("itchdotio", 0xFA5C5C),
        "java.com": Brand("openjdk", 0x000000),
        "jira.com": Brand("jira", 0x0052CC),
        "joinmastodon.org": Brand("mastodon", 0x6364FF),
        "jsfiddle.net": Brand("jsfiddle", 0x0084FF),
        "kaggle.com": Brand("kaggle", 0x20BEFF),
        "kernel.org": Brand("linux", 0xFCC624),
        "khanacademy.org": Brand("khanacademy", 0x14BF96),
        "kick.com": Brand("kick", 0x53FC19),
        "kubernetes.io": Brand("kubernetes", 0x326CE5),
        "lastpass.com": Brand("lastpass", 0xD32D27),
        "leetcode.com": Brand("leetcode", 0xFFA116),
        "lemmy.world": Brand("lemmy", 0x000000),
        "letterboxd.com": Brand("letterboxd", 0x202830),
        "line.me": Brand("line", 0x00C300),
        "linear.app": Brand("linear", 0x5E6AD2),
        "loom.com": Brand("loom", 0x625DF5),
        "lyft.com": Brand("lyft", 0xFF00BF),
        "mail.google.com": Brand("gmail", 0xEA4335),
        "mailchimp.com": Brand("mailchimp", 0xFFE01B),
        "maps.google.com": Brand("googlemaps", 0x4285F4),
        "mastodon.social": Brand("mastodon", 0x6364FF),
        "matrix.org": Brand("matrix", 0x000000),
        "max.com": Brand("hbo", 0x000000),
        "medium.com": Brand("medium", 0x000000),
        "meet.google.com": Brand("googlemeet", 0x00897B),
        "meetup.com": Brand("meetup", 0xED1C40),
        "miro.com": Brand("miro", 0x050038),
        "mongodb.com": Brand("mongodb", 0x47A248),
        "music.apple.com": Brand("applemusic", 0xFA243C),
        "mysql.com": Brand("mysql", 0x4479A1),
        "netflix.com": Brand("netflix", 0xE50914),
        "netlify.com": Brand("netlify", 0x00C7B7),
        "news.ycombinator.com": Brand("ycombinator", 0xF0652F),
        "nextdoor.com": Brand("nextdoor", 0x8ED500),
        "nextjs.org": Brand("nextdotjs", 0x000000),
        "nodejs.org": Brand("nodedotjs", 0x5FA04E),
        "notion.com": Brand("notion", 0x000000),
        "notion.so": Brand("notion", 0x000000),
        "npmjs.com": Brand("npm", 0xCB3837),
        "nytimes.com": Brand("newyorktimes", 0x000000),
        "obsidian.md": Brand("obsidian", 0x7C3AED),
        "ollama.com": Brand("ollama", 0x000000),
        "onlyfans.com": Brand("onlyfans", 0x00AFF0),
        "open.spotify.com": Brand("spotify", 0x1ED760),
        "patreon.com": Brand("patreon", 0x000000),
        "paypal.com": Brand("paypal", 0x002991),
        "perplexity.ai": Brand("perplexity", 0x1FB8CD),
        "photos.google.com": Brand("googlephotos", 0x4285F4),
        "php.net": Brand("php", 0x777BB4),
        "pinterest.com": Brand("pinterest", 0xBD081C),
        "play.google.com": Brand("googleplay", 0x414141),
        "playstation.com": Brand("playstation", 0x0070D1),
        "plex.tv": Brand("plex", 0xEBAF00),
        "postgresql.org": Brand("postgresql", 0x4169E1),
        "posthog.com": Brand("posthog", 0x000000),
        "postman.com": Brand("postman", 0xFF6C37),
        "producthunt.com": Brand("producthunt", 0xDA552F),
        "proton.me": Brand("proton", 0x6D4AFF),
        "protonmail.com": Brand("protonmail", 0x6D4AFF),
        "pypi.org": Brand("pypi", 0x3775A9),
        "python.org": Brand("python", 0x3776AB),
        "quora.com": Brand("quora", 0xB92B27),
        "railway.app": Brand("railway", 0x0B0D0E),
        "raycast.com": Brand("raycast", 0xFF6363),
        "react.dev": Brand("react", 0x61DAFB),
        "reactjs.org": Brand("react", 0x61DAFB),
        "reddit.com": Brand("reddit", 0xFF4500),
        "redis.io": Brand("redis", 0xFF4438),
        "render.com": Brand("render", 0x000000),
        "replicate.com": Brand("replicate", 0x000000),
        "replit.com": Brand("replit", 0xF26207),
        "robinhood.com": Brand("robinhood", 0xCCFF00),
        "roblox.com": Brand("roblox", 0x000000),
        "rottentomatoes.com": Brand("rottentomatoes", 0xFA320A),
        "ruby-lang.org": Brand("ruby", 0xCC342D),
        "rumble.com": Brand("rumble", 0x85C742),
        "rust-lang.org": Brand("rust", 0x000000),
        "sentry.io": Brand("sentry", 0x362D59),
        "sheets.google.com": Brand("googlesheets", 0x34A853),
        "shopify.com": Brand("shopify", 0x7AB55C),
        "signal.org": Brand("signal", 0x3B45FD),
        "snapchat.com": Brand("snapchat", 0xFFFC00),
        "soundcloud.com": Brand("soundcloud", 0xFF5500),
        "spotify.com": Brand("spotify", 0x1ED760),
        "spotify.link": Brand("spotify", 0x1ED760),
        "sqlite.org": Brand("sqlite", 0x003B57),
        "squarespace.com": Brand("squarespace", 0x000000),
        "stackexchange.com": Brand("stackexchange", 0x1E5397),
        "stackoverflow.com": Brand("stackoverflow", 0xF58025),
        "steampowered.com": Brand("steam", 0x000000),
        "strava.com": Brand("strava", 0xFC4C02),
        "stripe.com": Brand("stripe", 0x635BFF),
        "substack.com": Brand("substack", 0xFF6719),
        "supabase.com": Brand("supabase", 0x3FCF8E),
        "svelte.dev": Brand("svelte", 0xFF3E00),
        "swagger.io": Brand("swagger", 0x85EA2D),
        "swift.org": Brand("swift", 0xF05138),
        "t.me": Brand("telegram", 0x26A5E4),
        "tailwindcss.com": Brand("tailwindcss", 0x06B6D4),
        "target.com": Brand("target", 0xCC0000),
        "techcrunch.com": Brand("techcrunch", 0x029F00),
        "telegram.org": Brand("telegram", 0x26A5E4),
        "theguardian.com": Brand("theguardian", 0x052962),
        "threads.com": Brand("threads", 0x000000),
        "threads.net": Brand("threads", 0x000000),
        "tidal.com": Brand("tidal", 0x000000),
        "tiktok.com": Brand("tiktok", 0x000000),
        "todoist.com": Brand("todoist", 0xE44332),
        "trello.com": Brand("trello", 0x0052CC),
        "trustpilot.com": Brand("trustpilot", 0x00B67A),
        "tumblr.com": Brand("tumblr", 0x36465D),
        "twitch.tv": Brand("twitch", 0x9146FF),
        "twitter.com": Brand("x", 0x000000),
        "typeform.com": Brand("typeform", 0x262627),
        "uber.com": Brand("uber", 0x000000),
        "ubuntu.com": Brand("ubuntu", 0xE95420),
        "udemy.com": Brand("udemy", 0xA435F0),
        "unity.com": Brand("unity", 0xFFFFFF),
        "upwork.com": Brand("upwork", 0x6FDA44),
        "v0.dev": Brand("vercel", 0x000000),
        "venmo.com": Brand("venmo", 0x008CFF),
        "vercel.com": Brand("vercel", 0x000000),
        "vimeo.com": Brand("vimeo", 0x1AB7EA),
        "vk.com": Brand("vk", 0x0077FF),
        "vuejs.org": Brand("vuedotjs", 0x4FC08D),
        "w3schools.com": Brand("w3schools", 0x04AA6D),
        "wa.me": Brand("whatsapp", 0x25D366),
        "web.whatsapp.com": Brand("whatsapp", 0x25D366),
        "webflow.com": Brand("webflow", 0x146EF5),
        "wechat.com": Brand("wechat", 0x07C160),
        "weibo.com": Brand("sinaweibo", 0xE6162D),
        "whatsapp.com": Brand("whatsapp", 0x25D366),
        "wikipedia.org": Brand("wikipedia", 0x000000),
        "wix.com": Brand("wix", 0x0C6EFC),
        "wordpress.com": Brand("wordpress", 0x21759B),
        "wordpress.org": Brand("wordpress", 0x21759B),
        "x.com": Brand("x", 0x000000),
        "ycombinator.com": Brand("ycombinator", 0xF0652F),
        "yelp.com": Brand("yelp", 0xFF1A1A),
        "youtu.be": Brand("youtube", 0xFF0000),
        "youtube.com": Brand("youtube", 0xFF0000),
        "zapier.com": Brand("zapier", 0xFF4F00),
        "zillow.com": Brand("zillow", 0x006AFF),
        "zoom.us": Brand("zoom", 0x0B5CFF),
    ]
}

/// A brand mark drawn straight onto the card, sized to sit where an app icon
/// would.
///
/// No plate behind it. A white tile reads as a sticker pasted over the glass
/// and clashes with the real app icons sitting in the same column.
///
/// The mark keeps its brand colour whenever that colour is legible against the
/// skin. Marks that are near-black (GitHub, TikTok, X) or near-white would
/// disappear into the card, so those take the skin's own foreground instead.
struct SiteIconTile: View {
    @Environment(\.skin) private var skin
    let brand: SiteIcon.Brand
    var size: CGFloat = 18

    var body: some View {
        Image("SiteIcons/" + brand.slug)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }

    /// Brand colour when it stands out, the skin's own ink when it would not.
    private var tint: Color {
        let luminance = 0.2126 * Double((brand.hex >> 16) & 0xFF) / 255
            + 0.7152 * Double((brand.hex >> 8) & 0xFF) / 255
            + 0.0722 * Double(brand.hex & 0xFF) / 255
        return (0.16...0.88).contains(luminance) ? Color(hex: brand.hex) : skin.hi
    }
}
