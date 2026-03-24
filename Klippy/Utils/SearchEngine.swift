import Foundation
import CoreData
import Combine

class SearchEngine: ObservableObject {

    // MARK: - Search Configuration
    private struct SearchConfig {
        static let maxResults = 500
        static let cacheTimeout: TimeInterval = 30
        static let minQueryLength = 1
        static let debounceDelay: TimeInterval = 0.15
        static let broadFetchMultiplier = 3
        static let fuzzyFetchMultiplier = 6
        static let fuzzyMinTokenLength = 4
        static let fuzzyMaxDistance = 2
        static let fuzzyMinPrimaryResults = 20
    }

    // MARK: - Properties
    private let backgroundContext: NSManagedObjectContext
    private var searchCache: [String: CachedSearchResult] = [:]
    private var searchSubject = PassthroughSubject<SearchQuery, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var currentSearchID: UUID?

    @Published var isSearching = false
    @Published var searchResults: [ClipboardItemViewModel] = []
    @Published var searchStats: SearchStats = SearchStats()

    // MARK: - Search Query Structure
    struct DateRange: Hashable {
        let start: Date
        let end: Date
    }

    struct SearchQuery: Hashable {
        let text: String
        let category: ContentCategory
        let dateRange: DateRange?
        let limit: Int
    }

    // MARK: - Search Results Cache
    private struct CachedSearchResult {
        let results: [ClipboardItemViewModel]
        let timestamp: Date
        let stats: SearchStats

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > SearchConfig.cacheTimeout
        }
    }

    // MARK: - Search Statistics
    struct SearchStats {
        var totalMatches: Int = 0
        var searchTime: TimeInterval = 0
        var cacheHit: Bool = false
    }

    // MARK: - Initialization
    init() {
        self.backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        setupSearchDebouncing()
    }

    private func setupSearchDebouncing() {
        searchSubject
            .debounce(for: .seconds(SearchConfig.debounceDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Search Interface

    func search(
        query: String,
        category: ContentCategory = .all,
        dateRange: DateRange? = nil,
        limit: Int = 100
    ) -> [ClipboardItemViewModel] {

        let searchQuery = SearchQuery(
            text: query.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            dateRange: dateRange,
            limit: min(limit, SearchConfig.maxResults)
        )

        // Check cache first
        let cacheKey = generateCacheKey(for: searchQuery)
        if let cachedResult = searchCache[cacheKey], !cachedResult.isExpired {
            return cachedResult.results
        }

        // Empty query uses recent-memory cache for low-latency browsing
        if (searchQuery.text.isEmpty || searchQuery.text.count < SearchConfig.minQueryLength) &&
            searchQuery.dateRange == nil {
            return ClipboardManager.shared.getItemsFromCache(
                matching: searchQuery.text,
                category: searchQuery.category,
                limit: searchQuery.limit
            )
        }

        // Fire async search via debounce — never block the main thread
        searchSubject.send(searchQuery)

        // Return stale cache or empty while async search runs
        return searchResults
    }

    func updateSearchQuery(_ query: String) {
        let searchQuery = SearchQuery(
            text: query,
            category: .all,
            dateRange: nil,
            limit: 100
        )
        searchSubject.send(searchQuery)
    }

    // MARK: - Core Search Implementation

    private func performSearch(_ query: SearchQuery) {
        let searchID = UUID()
        currentSearchID = searchID
        let startTime = Date()
        isSearching = true

        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            // Bail if a newer search was requested
            guard self.currentSearchID == searchID else { return }

            do {
                let results = try self.executeSearch(query)
                let searchTime = Date().timeIntervalSince(startTime)

                // Bail if superseded
                guard self.currentSearchID == searchID else { return }

                let stats = SearchStats(
                    totalMatches: results.count,
                    searchTime: searchTime,
                    cacheHit: false
                )

                // Cache results
                let cacheKey = self.generateCacheKey(for: query)
                self.searchCache[cacheKey] = CachedSearchResult(
                    results: results,
                    timestamp: Date(),
                    stats: stats
                )

                self.cleanExpiredCache()

                DispatchQueue.main.async {
                    self.searchResults = results
                    self.searchStats = stats
                    self.isSearching = false
                }

            } catch {
                print("Search error: \(error)")
                DispatchQueue.main.async {
                    self.isSearching = false
                }
            }
        }
    }

    private func executeSearch(_ query: SearchQuery) throws -> [ClipboardItemViewModel] {
        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.returnsObjectsAsFaults = false

        // Build predicate
        var predicates: [NSPredicate] = []

        // Text search
        if !query.text.isEmpty {
            let searchPredicate = buildTextSearchPredicate(for: query.text)
            predicates.append(searchPredicate)
        }

        // Category filter
        if query.category != .all {
            predicates.append(NSPredicate(format: "contentType == %d", query.category.rawValue))
        }

        // Date range filter
        if let dateRange = query.dateRange {
            predicates.append(
                NSPredicate(
                    format: "createdAt >= %@ AND createdAt < %@",
                    dateRange.start as NSDate,
                    dateRange.end as NSDate
                )
            )
        }

        // Combine predicates
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        // Sort by recency first, then relevance
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false),
            NSSortDescriptor(keyPath: \ClipboardItem.usageCount, ascending: false)
        ]

        // Limit results — don't over-fetch
        request.fetchLimit = min(
            SearchConfig.maxResults,
            query.limit * SearchConfig.broadFetchMultiplier
        )

        // Don't fetch heavy image data during search
        request.propertiesToFetch = ["id", "content", "contentType", "contentHash", "searchableContent", "createdAt", "lastAccessedAt", "usageCount", "sourceApplication", "tags", "isImage", "imageWidth", "imageHeight"]

        // Execute search
        let primaryResults = try backgroundContext.fetch(request).map { ClipboardItemViewModel(from: $0) }
        var combinedResults = primaryResults

        // Only do fuzzy search if primary results are insufficient and query is long enough
        if !query.text.isEmpty &&
            combinedResults.count < SearchConfig.fuzzyMinPrimaryResults &&
            query.text.count >= SearchConfig.fuzzyMinTokenLength {
            let existingIDs = Set(combinedResults.map(\.id))
            let fuzzyResults = try fetchFuzzyCandidates(for: query, excludingIDs: existingIDs)
            combinedResults.append(contentsOf: fuzzyResults)
        }

        return rankResults(
            items: combinedResults,
            for: query.text,
            limit: query.limit
        )
    }

    private func buildTextSearchPredicate(for text: String) -> NSPredicate {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return NSPredicate(value: true) }

        let normalizedTerms = trimmedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let exactPredicate = NSPredicate(
            format: "(searchableContent CONTAINS[cd] %@) OR (content CONTAINS[cd] %@)",
            trimmedText,
            trimmedText
        )

        guard !normalizedTerms.isEmpty else { return exactPredicate }

        let termPredicates = normalizedTerms.map { term in
            NSPredicate(
                format: "(searchableContent CONTAINS[cd] %@) OR (content CONTAINS[cd] %@)",
                term,
                term
            )
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            exactPredicate,
            NSCompoundPredicate(andPredicateWithSubpredicates: termPredicates)
        ])
    }

    private func rankResults(items: [ClipboardItemViewModel], for query: String, limit: Int) -> [ClipboardItemViewModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let sorted = items.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.usageCount > rhs.usageCount
            }
            return Array(sorted.prefix(limit))
        }

        let normalizedQuery = normalizeForFuzzy(query)
        let queryTokens = normalizedSearchTokens(from: query)

        let ranked = items.sorted { lhs, rhs in
            let leftScore = score(item: lhs, query: normalizedQuery, tokens: queryTokens)
            let rightScore = score(item: rhs, query: normalizedQuery, tokens: queryTokens)

            if leftScore != rightScore {
                return leftScore > rightScore
            }

            return lhs.createdAt > rhs.createdAt
        }

        return Array(ranked.prefix(limit))
    }

    private func score(item: ClipboardItemViewModel, query: String, tokens: [String]) -> Int {
        // Only score against a prefix of the content to avoid expensive ops on huge strings
        let contentPrefix = String(item.content.prefix(300))
        let normalizedContent = normalizeForFuzzy(contentPrefix)
        var score = 0

        // Relevance scoring — kept tight so recency can compete
        if normalizedContent == query {
            score += 500
        } else if normalizedContent.hasPrefix(query) {
            score += 300
        } else if normalizedContent.contains(query) {
            score += 100
        }

        if !tokens.isEmpty, tokens.allSatisfy({ normalizedContent.contains($0) }) {
            score += 50
        }

        // Only run expensive fuzzy matching for longer queries and limited items
        if query.count >= SearchConfig.fuzzyMinTokenLength && !normalizedContent.isEmpty {
            let contentTokens = normalizedSearchTokens(from: contentPrefix)

            for token in tokens.prefix(2) where token.count >= SearchConfig.fuzzyMinTokenLength {
                if contentTokens.contains(token) {
                    score += 30
                    continue
                }

                if let distance = bestEditDistance(
                    token: token,
                    in: contentTokens,
                    maxDistance: SearchConfig.fuzzyMaxDistance
                ) {
                    score += (SearchConfig.fuzzyMaxDistance + 1 - distance) * 15
                }
            }
        }

        // Recency bonus — items from the last 7 days get up to 200 points
        let ageInDays = Date().timeIntervalSince(item.createdAt) / 86400
        if ageInDays < 7 {
            score += Int((7.0 - ageInDays) / 7.0 * 200)
        }

        return score
    }

    private func fetchFuzzyCandidates(
        for query: SearchQuery,
        excludingIDs: Set<UUID>
    ) throws -> [ClipboardItemViewModel] {
        guard let fuzzyTextPredicate = buildFuzzyFallbackPredicate(for: query.text) else {
            return []
        }

        let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
        request.returnsObjectsAsFaults = false
        var predicates: [NSPredicate] = [fuzzyTextPredicate]

        if query.category != .all {
            predicates.append(NSPredicate(format: "contentType == %d", query.category.rawValue))
        }

        if let dateRange = query.dateRange {
            predicates.append(
                NSPredicate(
                    format: "createdAt >= %@ AND createdAt < %@",
                    dateRange.start as NSDate,
                    dateRange.end as NSDate
                )
            )
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ClipboardItem.createdAt, ascending: false)
        ]
        request.fetchLimit = min(
            SearchConfig.maxResults,
            query.limit * SearchConfig.fuzzyFetchMultiplier
        )

        let fetched = try backgroundContext.fetch(request).map { ClipboardItemViewModel(from: $0) }
        return fetched.filter { !excludingIDs.contains($0.id) }
    }

    private func buildFuzzyFallbackPredicate(for text: String) -> NSPredicate? {
        let tokens = normalizedSearchTokens(from: text)
            .filter { $0.count >= SearchConfig.fuzzyMinTokenLength }

        guard !tokens.isEmpty else { return nil }

        let fuzzyPredicates = tokens.prefix(2).map { token -> NSPredicate in
            let interleaved = "%" + token.map { String($0) }.joined(separator: "%") + "%"
            return NSPredicate(
                format: "(searchableContent LIKE[cd] %@) OR (content LIKE[cd] %@)",
                interleaved,
                interleaved
            )
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: fuzzyPredicates)
    }

    private func normalizeForFuzzy(_ text: String) -> String {
        let compact = text.lowercased().prefix(300)
        return String(compact.filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSearchTokens(from text: String) -> [String] {
        normalizeForFuzzy(text)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private func bestEditDistance(token: String, in candidates: [String], maxDistance: Int) -> Int? {
        var best: Int?

        for candidate in candidates where abs(candidate.count - token.count) <= maxDistance + 1 {
            guard candidate.first == token.first else { continue }
            if let distance = boundedLevenshtein(token, candidate, maxDistance: maxDistance) {
                if best == nil || distance < best! {
                    best = distance
                }
            }
        }

        return best
    }

    private func boundedLevenshtein(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int? {
        if lhs == rhs { return 0 }
        if abs(lhs.count - rhs.count) > maxDistance { return nil }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)

        for i in 1...lhsChars.count {
            current[0] = i
            var rowMinimum = current[0]

            for j in 1...rhsChars.count {
                let substitutionCost = lhsChars[i - 1] == rhsChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[j])
            }

            if rowMinimum > maxDistance {
                return nil
            }

            swap(&previous, &current)
        }

        return previous[rhsChars.count] <= maxDistance ? previous[rhsChars.count] : nil
    }

    // MARK: - Cache Management

    private func generateCacheKey(for query: SearchQuery) -> String {
        let dateKey: String
        if let range = query.dateRange {
            dateKey = "\(range.start.timeIntervalSince1970)-\(range.end.timeIntervalSince1970)"
        } else {
            dateKey = "all-time"
        }

        return "\(query.text)|\(query.category.rawValue)|\(dateKey)|\(query.limit)|\(ClipboardManager.shared.totalItemCount)"
    }

    private func cleanExpiredCache() {
        let expiredKeys = searchCache.compactMap { key, value in
            value.isExpired ? key : nil
        }

        expiredKeys.forEach { searchCache.removeValue(forKey: $0) }
    }

    func clearCache() {
        searchCache.removeAll()
    }
}
