import SwiftUI

/// The Date menu from the mockup: presets, then a collapsible month grid where
/// tapping two days sets a custom range.
struct DateRangePopover: View {
    @Binding var filter: ItemDateFilter
    @Binding var customStart: Date
    @Binding var customEnd: Date
    let onDismiss: () -> Void

    @Environment(\.skin) private var skin

    @State private var showingCustom = false
    @State private var visibleMonth: Date = Date()
    /// First tap of a new range; nil once both ends are chosen.
    @State private var pendingStart: Date?

    private let cal = Calendar.current

    var body: some View {
        // One view at a time. Stacking the presets above the calendar made the
        // menu taller than the panel, so the Show button needed scrolling to
        // reach. Opening Custom swaps the list out for the calendar instead.
        Group {
            if showingCustom {
                calendar
            } else {
                presets
            }
        }
        .frame(width: 264)
        .fixedSize(horizontal: false, vertical: true)
        .background(skin.pop)
    }

    private var presets: some View {
        VStack(spacing: 2) {
            ForEach(ItemDateFilter.quickCases) { option in
                row(option)
            }

            Rectangle()
                .fill(skin.line)
                .frame(height: 1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)

            customRow
        }
        .padding(6)
    }

    private var calendar: some View {
        VStack(spacing: 2) {
            Button {
                showingCustom = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Custom range")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13.5))
                .foregroundStyle(skin.hi)
                .padding(.horizontal, 11)
                .frame(height: 32)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(skin.line)
                .frame(height: 1)
                .padding(.horizontal, 11)
                .padding(.vertical, 3)

            monthGrid
        }
        .padding(6)
    }

    // MARK: - Presets

    private func row(_ option: ItemDateFilter) -> some View {
        Button {
            filter = option
            showingCustom = false
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Text(option.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(option == filter ? 1 : 0)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(skin.hi)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(option == filter ? skin.sel : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var customRow: some View {
        Button {
            showingCustom.toggle()
            if showingCustom { visibleMonth = customStart }
        } label: {
            HStack(spacing: 8) {
                Text("Custom range")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if filter == .custom {
                    Text(rangeLabel)
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(skin.mid)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(skin.mid)
                    .rotationEffect(.degrees(showingCustom ? 180 : 0))
            }
            .font(.system(size: 13.5))
            .foregroundStyle(skin.hi)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(filter == .custom ? skin.sel : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar

    private var monthGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                monthButton("chevron.left") { shiftMonth(-1) }
                Text(Self.monthTitle.string(from: visibleMonth))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(skin.hi)
                    .frame(maxWidth: .infinity)
                monthButton("chevron.right") { shiftMonth(1) }
            }
            .padding(.bottom, 10)

            HStack(spacing: 0) {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(skin.low)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: 2) {
                ForEach(monthDays.indices, id: \.self) { index in
                    dayCell(monthDays[index])
                }
            }

            Button(action: applyRange) {
                Text("Show \(rangeLabel)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(skin.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(skin.accent,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 5)
        .padding(.top, 4)
    }

    private func monthButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(skin.mid)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let position = position(of: day)
            Button {
                pick(day)
            } label: {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 13, weight: position.isEdge ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(position.isEdge ? skin.ink : skin.hi)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(dayBackground(position))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 30)
        }
    }

    @ViewBuilder
    private func dayBackground(_ position: DayPosition) -> some View {
        if position.isEdge {
            UnevenRoundedRectangle(
                topLeadingRadius: position.roundsLeading ? 10 : 0,
                bottomLeadingRadius: position.roundsLeading ? 10 : 0,
                bottomTrailingRadius: position.roundsTrailing ? 10 : 0,
                topTrailingRadius: position.roundsTrailing ? 10 : 0,
                style: .continuous
            )
            .fill(skin.accent)
        } else if position.isInside {
            Rectangle().fill(skin.sel)
        } else {
            Color.clear
        }
    }

    private struct DayPosition {
        var isStart = false
        var isEnd = false
        var isInside = false
        var isEdge: Bool { isStart || isEnd }
        var roundsLeading: Bool { isStart }
        var roundsTrailing: Bool { isEnd }
    }

    private func position(of day: Date) -> DayPosition {
        let start = cal.startOfDay(for: pendingStart ?? customStart)
        let end = pendingStart == nil ? cal.startOfDay(for: customEnd) : start
        let target = cal.startOfDay(for: day)

        var position = DayPosition()
        position.isStart = target == min(start, end)
        position.isEnd = target == max(start, end)
        position.isInside = target > min(start, end) && target < max(start, end)
        return position
    }

    private func pick(_ day: Date) {
        if let start = pendingStart {
            // Second tap closes the range, in whichever order it was drawn.
            customStart = min(start, day)
            customEnd = max(start, day)
            pendingStart = nil
        } else {
            pendingStart = day
            customStart = day
            customEnd = day
        }
    }

    private func applyRange() {
        pendingStart = nil
        filter = .custom
        showingCustom = false
        onDismiss()
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = shifted
        }
    }

    /// Leading blanks so the 1st lands under the right weekday, then the days.
    private var monthDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: visibleMonth),
              let first = cal.date(from: cal.dateComponents([.year, .month],
                                                                     from: visibleMonth))
        else { return [] }

        // Monday-first, matching the mockup's M T W T F S S header.
        let leading = (cal.component(.weekday, from: first) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            days.append(cal.date(byAdding: .day, value: offset, to: first))
        }
        return days
    }

    private var rangeLabel: String {
        let start = cal.startOfDay(for: customStart)
        let end = cal.startOfDay(for: customEnd)
        if start == end { return Self.dayMonth.string(from: start) }
        if cal.isDate(start, equalTo: end, toGranularity: .month) {
            let startDay = cal.component(.day, from: start)
            return "\(startDay)–\(Self.dayMonth.string(from: end))"
        }
        return "\(Self.dayMonth.string(from: start))–\(Self.dayMonth.string(from: end))"
    }

    private static let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    private static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
