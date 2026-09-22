import Foundation
import Combine

/// The kinds of thing the user has told Klippy never to write down.
///
/// A shape, not a source: card numbers wherever they came from, API keys
/// wherever they came from. The classifier already works out what a clip is on
/// the way in, so the same answer can decide whether to keep it at all.
///
/// This is the part "Ignore password managers" cannot do. That switch only
/// skips clips an app has marked with `org.nspasteboard.ConcealedType`, and a
/// tool that handles secrets but copies as plain text is never marked, so the
/// clip lands in the history anyway. Excluding the kind catches it regardless
/// of which app it came from.
final class ExclusionStore: ObservableObject {
    static let shared = ExclusionStore()

    private static let kindsKey = "klippy.privacy.excludedKinds"

    private let defaults = UserDefaults.standard

    /// `ContentCategory` raw values.
    @Published private(set) var kinds: Set<Int16> = []

    private init() {
        kinds = Set((defaults.array(forKey: Self.kindsKey) as? [Int] ?? []).map(Int16.init))
    }

    // MARK: - Kinds

    func excludes(category: ContentCategory) -> Bool {
        kinds.contains(category.rawValue)
    }

    func setExcluded(_ excluded: Bool, kind: ContentCategory) {
        if excluded { kinds.insert(kind.rawValue) } else { kinds.remove(kind.rawValue) }
        defaults.set(kinds.map { Int($0) }, forKey: Self.kindsKey)
    }

    /// The kinds worth offering. Not every category: "Text" would switch off
    /// most of the app, and "All" and "Merged" are not things you copy.
    var summary: String {
        kinds.isEmpty ? "Nothing excluded"
                      : "\(kinds.count) kind\(kinds.count == 1 ? "" : "s")"
    }

    static let offerable: [ContentCategory] = [
        .apiKey, .paymentCard, .email, .phone, .address,
        .ipAddress, .identifier, .url, .image, .file, .code
    ]
}
