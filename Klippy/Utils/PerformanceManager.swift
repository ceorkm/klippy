import Foundation
import CoreData
import os.log

class PerformanceManager {
    static let shared = PerformanceManager()
    
    // MARK: - Configuration
    private struct Config {
        static let maxMemoryUsage: UInt64 = 500 * 1024 * 1024 // 500MB
        static let cleanupInterval: TimeInterval = 300 // 5 minutes
        static let maxCacheAge: TimeInterval = 3600 // 1 hour
        static let batchSize = 1000
        static let maxItemsInMemory = 10000
    }
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.klippy.performance", category: "PerformanceManager")
    private var cleanupTimer: Timer?
    private var memoryWarningObserver: NSObjectProtocol?
    
    // Performance metrics
    @Published var memoryUsage: UInt64 = 0
    @Published var itemCount: Int = 0
    @Published var searchPerformance: SearchMetrics = SearchMetrics()
    
    struct SearchMetrics {
        var averageSearchTime: TimeInterval = 0
        var totalSearches: Int = 0
        var cacheHitRate: Double = 0
    }
    
    private init() {
        setupMemoryMonitoring()
        startPerformanceMonitoring()
    }
    
    deinit {
        cleanupTimer?.invalidate()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryMonitoring() {
        // Monitor memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func startPerformanceMonitoring() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: Config.cleanupInterval, repeats: true) { [weak self] _ in
            self?.performMaintenanceTasks()
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("Memory warning received, performing aggressive cleanup")
        
        Task {
            await performAggressiveCleanup()
        }
    }
    
    private func performMaintenanceTasks() {
        Task {
            await performRoutineCleanup()
            await updateMemoryUsage()
            await optimizeDatabase()
        }
    }
    
    // MARK: - Cleanup Operations
    
    @MainActor
    private func performRoutineCleanup() async {
        logger.info("Performing routine cleanup")
        
        // Clear expired search cache
        SearchEngine().clearCache()
        
        // Clean up old clipboard items if memory usage is high
        if memoryUsage > Config.maxMemoryUsage * 3 / 4 {
            await cleanupOldItems()
        }
        
        // Force garbage collection
        autoreleasepool {
            // This block helps release any autoreleased objects
        }
    }
    
    @MainActor
    private func performAggressiveCleanup() async {
        logger.warning("Performing aggressive cleanup due to memory pressure")
        
        // Clear all caches
        SearchEngine().clearCache()
        
        // Clean up old items more aggressively
        await cleanupOldItems(aggressively: true)
        
        // Clear clipboard manager cache
        ClipboardManager.shared.clearCache()
        
        // Force Core Data to release memory
        let context = PersistenceController.shared.container.viewContext
        context.refreshAllObjects()
    }
    
    private func cleanupOldItems(aggressively: Bool = false) async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await withCheckedContinuation { continuation in
            context.perform {
                let request: NSFetchRequest<ClipboardItem> = ClipboardItem.fetchRequest()
                
                // Determine cutoff date
                let cutoffDays = aggressively ? 30 : 90
                let cutoffDate = Calendar.current.date(byAdding: .day, value: -cutoffDays, to: Date())!
                
                request.predicate = NSPredicate(format: "lastAccessedAt < %@ AND usageCount == 0", cutoffDate as NSDate)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \ClipboardItem.lastAccessedAt, ascending: true)]
                request.fetchLimit = aggressively ? Config.batchSize * 5 : Config.batchSize
                
                do {
                    let itemsToDelete = try context.fetch(request)
                    
                    if !itemsToDelete.isEmpty {
                        self.logger.info("Cleaning up \(itemsToDelete.count) old clipboard items")
                        
                        for item in itemsToDelete {
                            context.delete(item)
                        }
                        
                        try context.save()
                    }
                } catch {
                    self.logger.error("Failed to cleanup old items: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Database Optimization
    
    private func optimizeDatabase() async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await withCheckedContinuation { continuation in
            context.perform {
                // Vacuum the database periodically
                let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "ClipboardItem"))
                request.resultType = .resultTypeCount
                
                // This doesn't actually delete anything, but triggers Core Data optimizations
                do {
                    _ = try context.execute(request)
                } catch {
                    self.logger.error("Database optimization failed: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Memory Usage Tracking
    
    private func updateMemoryUsage() async {
        let usage = getMemoryUsage()
        
        await MainActor.run {
            self.memoryUsage = usage
        }
        
        if usage > Config.maxMemoryUsage {
            logger.warning("Memory usage (\(usage / 1024 / 1024)MB) exceeds limit (\(Config.maxMemoryUsage / 1024 / 1024)MB)")
            await performAggressiveCleanup()
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    // MARK: - Performance Metrics
    
    func recordSearchPerformance(searchTime: TimeInterval, cacheHit: Bool) {
        searchPerformance.totalSearches += 1
        
        // Update average search time
        let totalTime = searchPerformance.averageSearchTime * Double(searchPerformance.totalSearches - 1) + searchTime
        searchPerformance.averageSearchTime = totalTime / Double(searchPerformance.totalSearches)
        
        // Update cache hit rate
        let totalCacheHits = searchPerformance.cacheHitRate * Double(searchPerformance.totalSearches - 1) + (cacheHit ? 1.0 : 0.0)
        searchPerformance.cacheHitRate = totalCacheHits / Double(searchPerformance.totalSearches)
        
        logger.info("Search performance: \(searchTime * 1000)ms, cache hit: \(cacheHit)")
    }
    
    // MARK: - Batch Operations
    
    func performBatchOperation<T>(_ items: [T], batchSize: Int = Config.batchSize, operation: @escaping ([T]) async throws -> Void) async throws {
        let chunks = items.chunked(into: batchSize)
        
        for chunk in chunks {
            try await operation(chunk)
            
            // Small delay to prevent overwhelming the system
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    // MARK: - Public Interface
    
    func getPerformanceReport() -> String {
        let memoryMB = Double(memoryUsage) / 1024 / 1024
        
        return """
        Klippy Performance Report
        ========================
        Memory Usage: \(String(format: "%.1f", memoryMB))MB
        Total Items: \(itemCount)
        Average Search Time: \(String(format: "%.1f", searchPerformance.averageSearchTime * 1000))ms
        Cache Hit Rate: \(String(format: "%.1f", searchPerformance.cacheHitRate * 100))%
        Total Searches: \(searchPerformance.totalSearches)
        """
    }
    
    func clearAllCaches() {
        SearchEngine().clearCache()
        ClipboardManager.shared.clearCache()
        logger.info("All caches cleared")
    }
}

// MARK: - Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension ClipboardManager {
    func clearCache() {
        // Clear internal caches
        itemCache.removeAll()
        recentHashes.removeAll()
    }
}
