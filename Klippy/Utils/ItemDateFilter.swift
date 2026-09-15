import Foundation

/// The date ranges the history list can be narrowed to.
///
/// Lived in the old ContentView until that screen was replaced by the panel.
enum ItemDateFilter: String, CaseIterable, Identifiable {
    case allTime
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisMonth
    case custom

    var id: String { rawValue }

    static var quickCases: [ItemDateFilter] {
        [.allTime, .today, .yesterday, .last7Days, .last30Days, .thisMonth]
    }

    var displayName: String {
        switch self {
        case .allTime: return "Any time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .thisMonth: return "This month"
        case .custom: return "Custom"
        }
    }

    func makeRange(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        customStartDate: Date = Date(),
        customEndDate: Date = Date()
    ) -> SearchEngine.DateRange? {
        switch self {
        case .allTime:
            return nil

        case .today:
            let start = calendar.startOfDay(for: referenceDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return SearchEngine.DateRange(start: start, end: end)

        case .yesterday:
            let end = calendar.startOfDay(for: referenceDate)
            guard let start = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return SearchEngine.DateRange(start: start, end: end)

        case .last7Days:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .last30Days:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: referenceDate)) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: referenceDate)
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return SearchEngine.DateRange(start: start, end: end)

        case .custom:
            let from = min(customStartDate, customEndDate)
            let to = max(customStartDate, customEndDate)

            let start = calendar.startOfDay(for: from)
            let endBase = calendar.startOfDay(for: to)
            guard let end = calendar.date(byAdding: .day, value: 1, to: endBase) else {
                return nil
            }

            return SearchEngine.DateRange(start: start, end: end)
        }
    }
}
