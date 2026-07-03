import Defaults
import AppKit
import SwiftUI

final class CalendarWheelScrollTarget: ObservableObject {
    weak var scrollView: NSScrollView?
    var handleScrollEvent: ((NSEvent) -> Bool)?

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        handleScrollEvent?(event) ?? false
    }
}

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 2
    var showsText: Bool = true
}

struct WheelPicker: View {
    @EnvironmentObject var vm: QuartzViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var scrollOffset: CGFloat = 0
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    @State private var containerWidth: CGFloat = 0
    @State private var isSyncingExternalScroll = false
    @State private var lastExternalSelectedIndex: Int?
    @State private var externalGestureAnchorIndex: Int?
    @State private var externalGesturePhysicalDelta: CGFloat = 0
    @State private var externalScrollGeneration = 0
    @State private var isSuppressingExternalMomentum = false
    @State private var externalSnapTask: Task<Void, Never>?
    @State private var hasResolvedInitialOffset = false
    let config: Config
    let centerTrigger: Int
    let externalScrollTarget: CalendarWheelScrollTarget?

    private let itemWidth: CGFloat = 31
    private let selectionSpring = Animation.spring(response: 0.32, dampingFraction: 0.72)
    private let externalMicroSwipeThreshold: CGFloat = 0.14
    private let externalNormalSwipeThreshold: CGFloat = 0.5
    private let externalSnapDuration: TimeInterval = 0.12
    private let externalIdleSnapDelay: TimeInterval = 0.11
    private let externalMomentumSnapThreshold: CGFloat = 1.35
    private var itemStride: CGFloat { itemWidth + config.spacing }

    private var sidePadding: CGFloat {
        containerWidth > itemWidth ? (containerWidth - itemWidth) / 2 : 0
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: config.spacing) {
                ForEach(0..<totalDateItems(), id: \.self) { index in
                    let date = dateForItemIndex(index: index)
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

                    dateButton(date: date, isSelected: isSelected, id: index) {
                        selectedDate = date
                        byClick = true
                        snapToIndex(index, animated: true)
                    }
                }
            }
            .padding(.horizontal, sidePadding(for: geo.size.width))
            .offset(x: hasResolvedInitialOffset ? scrollOffset : offsetForIndex(indexForDate(selectedDate)))
            .frame(width: geo.size.width, height: 60, alignment: .leading)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        guard geo.size.width > 0 else { return }
                        let rawIndex = (value.location.x - scrollOffset - sidePadding(for: geo.size.width) - (itemWidth / 2)) / itemStride
                        let targetIndex = max(0, min(Int(round(rawIndex)), totalDateItems() - 1))
                        let targetDate = dateForItemIndex(index: targetIndex)
                        if !Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                            selectedDate = targetDate
                        }
                        byClick = true
                        snapToIndex(targetIndex, animated: true)
                    }
            )
            .sensoryFeedback(.alignment, trigger: haptics)
            .onChange(of: selectedDate) { _, newValue in
                guard !isSyncingExternalScroll else { return }
                guard !byClick else {
                    byClick = false
                    return
                }
                snapToIndex(indexForDate(newValue), animated: true)
            }
            .onChange(of: geo.size.width) { _, width in
                containerWidth = width
                snapToIndex(indexForDate(selectedDate), animated: false)
            }
            .onAppear {
                containerWidth = geo.size.width
                snapToIndex(indexForDate(selectedDate), animated: false)
                externalScrollTarget?.handleScrollEvent = { event in
                    handleExternalScroll(event)
                }
                DispatchQueue.main.async {
                    hasResolvedInitialOffset = true
                }
            }
            .onChange(of: centerTrigger) { _, _ in
                snapToIndex(indexForDate(selectedDate), animated: false)
            }
            .onDisappear {
                externalScrollTarget?.handleScrollEvent = nil
                externalSnapTask?.cancel()
                externalSnapTask = nil
                hasResolvedInitialOffset = false
            }
        }
        .frame(height: 60)
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        DayCell(date: date, isSelected: isSelected, isToday: Calendar.current.isDateInToday(date))
            .onTapGesture { onClick() }
            .id(id)
    }

    private func handleExternalScroll(_ event: NSEvent) -> Bool {
        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY

        guard abs(horizontal) > abs(vertical) * 1.6 || (!event.momentumPhase.isEmpty && abs(horizontal) > abs(vertical)) else { return false }

        if externalGestureAnchorIndex == nil {
            externalGestureAnchorIndex = nearestIndexForCurrentOffset()
            lastExternalSelectedIndex = externalGestureAnchorIndex
            externalGesturePhysicalDelta = 0
            isSuppressingExternalMomentum = false
        }

        isSyncingExternalScroll = true
        let isMomentum = !event.momentumPhase.isEmpty
        if !isMomentum {
            externalGesturePhysicalDelta += horizontal
        } else if abs(externalGesturePhysicalDelta / itemStride) < externalNormalSwipeThreshold {
            isSuppressingExternalMomentum = true
        }

        if isSuppressingExternalMomentum {
            externalScrollGeneration += 1
            let generation = externalScrollGeneration
            scheduleExternalSnap(
                anchorIndex: externalGestureAnchorIndex ?? indexForDate(selectedDate),
                physicalDelta: externalGesturePhysicalDelta,
                generation: generation,
                delay: 0,
                animated: true
            )
            return true
        }

        let minOffset = offsetForIndex(totalDateItems() - 1)
        scrollOffset = min(0, max(minOffset, scrollOffset + horizontal))
        updateSelectionForCurrentOffset()

        externalScrollGeneration += 1
        let generation = externalScrollGeneration
        let delay = externalSnapDelay(for: event)
        scheduleExternalSnap(
            anchorIndex: externalGestureAnchorIndex ?? indexForDate(selectedDate),
            physicalDelta: externalGesturePhysicalDelta,
            generation: generation,
            delay: delay,
            animated: shouldAnimateExternalSnap(for: event)
        )

        return true
    }

    private func scheduleExternalSnap(
        anchorIndex: Int,
        physicalDelta: CGFloat,
        generation: Int,
        delay: TimeInterval,
        animated: Bool
    ) {
        externalSnapTask?.cancel()
        externalSnapTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            guard externalScrollGeneration == generation else { return }
            let target = finalTargetIndex(anchorIndex: anchorIndex, physicalDelta: physicalDelta)
            let targetDate = dateForItemIndex(index: target)
            lastExternalSelectedIndex = nil
            externalGestureAnchorIndex = nil
            externalGesturePhysicalDelta = 0
            isSuppressingExternalMomentum = false
            if !Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                selectedDate = targetDate
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
            snapToIndex(target, animated: animated)

            let settleDelay = animated ? externalSnapDuration + 0.01 : 0.01
            try? await Task.sleep(for: .seconds(settleDelay))
            if Task.isCancelled { return }
            guard externalScrollGeneration == generation else { return }
            isSyncingExternalScroll = false
            externalSnapTask = nil
        }
    }

    private func finalTargetIndex(anchorIndex: Int, physicalDelta: CGFloat) -> Int {
        let physicalDistance = abs(physicalDelta / itemStride)
        if physicalDistance >= externalMicroSwipeThreshold, physicalDistance < externalNormalSwipeThreshold {
            let direction = physicalDelta < 0 ? 1 : -1
            return max(0, min(anchorIndex + direction, totalDateItems() - 1))
        }

        return nearestIndexForCurrentOffset(anchorIndex: anchorIndex)
    }

    private func externalSnapDelay(for event: NSEvent) -> TimeInterval {
        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            return 0
        }

        if !event.momentumPhase.isEmpty {
            return externalIdleSnapDelay * 1.8
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            return 0.01
        }

        if event.phase.contains(.began) || event.phase.contains(.changed) {
            return externalIdleSnapDelay * 1.65
        }

        return externalIdleSnapDelay * 1.45
    }

    private func shouldAnimateExternalSnap(for event: NSEvent) -> Bool {
        true
    }

    private func snapToIndex(_ index: Int, animated: Bool) {
        let targetOffset = offsetForIndex(max(0, min(index, totalDateItems() - 1)))
        scrollPosition = index
        if animated {
            withAnimation(selectionSpring) {
                scrollOffset = targetOffset
            }
        } else {
            scrollOffset = targetOffset
        }
    }

    private func offsetForIndex(_ index: Int) -> CGFloat {
        -CGFloat(index) * itemStride
    }

    private func sidePadding(for width: CGFloat) -> CGFloat {
        width > itemWidth ? (width - itemWidth) / 2 : 0
    }

    private func nearestIndexForCurrentOffset(anchorIndex: Int? = nil, allowsMicroSnap: Bool = false) -> Int {
        let itemCount = totalDateItems()
        let rawIndex = -scrollOffset / itemStride
        if let anchorIndex {
            return sensitiveTargetIndex(
                from: rawIndex,
                itemCount: itemCount,
                anchorIndex: anchorIndex,
                allowsMicroSnap: allowsMicroSnap
            )
        }
        return max(0, min(Int(round(rawIndex)), itemCount - 1))
    }

    private func updateSelectionForCurrentOffset() {
        let targetIndex = nearestIndexForCurrentOffset(anchorIndex: externalGestureAnchorIndex)
        guard lastExternalSelectedIndex != targetIndex else { return }

        let targetDate = dateForItemIndex(index: targetIndex)
        lastExternalSelectedIndex = targetIndex
        if !Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
            selectedDate = targetDate
            if Defaults[.enableHaptics] { haptics.toggle() }
        }
    }

    private func sensitiveTargetIndex(
        from rawIndex: CGFloat,
        itemCount: Int,
        anchorIndex: Int,
        allowsMicroSnap: Bool
    ) -> Int {
        guard itemCount > 0 else { return 0 }

        let clampedAnchor = max(0, min(anchorIndex, itemCount - 1))
        let delta = rawIndex - CGFloat(clampedAnchor)

        let distance = abs(delta)
        let offset: Int
        if allowsMicroSnap, distance >= externalMicroSwipeThreshold, distance < externalNormalSwipeThreshold {
            offset = delta > 0 ? 1 : -1
        } else if distance < externalNormalSwipeThreshold {
            offset = 0
        } else {
            offset = Int(round(delta))
        }

        return max(0, min(clampedAnchor + offset, itemCount - 1))
    }

    private func indexForDate(_ date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        return max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
    }

    private func dateForItemIndex(index: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        return cal.date(byAdding: .day, value: index * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.72)
    private let circleSpring = Animation.spring(response: 0.32, dampingFraction: 1.0)

    var body: some View {
        VStack(spacing: 3) {
            Text(dayLetter)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.28))
                .animation(spring, value: isSelected)

            ZStack {
                Circle()
                    .fill(isSelected ? (isToday ? Color.red : Color.white) : Color.clear)
                    .frame(width: 27, height: 27)
                    .scaleEffect(isSelected ? 1.0 : 0.01)
                    .animation(circleSpring, value: isSelected)

                ZStack {
                    Text("\(date.date)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isToday ? Color.white : Color.black)
                        .opacity(isSelected ? 1.0 : 0.0)

                    Text("\(date.date)")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isToday ? Color.red : Color.white.opacity(0.55))
                        .opacity(isSelected ? 0.0 : 1.0)
                }
                .animation(spring, value: isSelected)
                .zIndex(1)
            }
            .frame(width: 29, height: 29)
        }
        .frame(width: 31, height: 60)
        .scaleEffect(isSelected ? 1.0 : 0.92)
        .opacity(isSelected ? 1.0 : 0.75)
        .animation(spring, value: isSelected)
        .contentShape(Rectangle())
    }

    private var dayLetter: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date).uppercased()
    }
}

private struct CalendarWheelScrollViewReader: NSViewRepresentable {
    let target: CalendarWheelScrollTarget?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolve(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolve(from: nsView)
    }

    private func resolve(from view: NSView) {
        for delay in [0.0, 0.02, 0.08, 0.16, 0.32] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                target?.scrollView = findScrollView(startingAt: view)
            }
        }
    }

    private func findScrollView(startingAt view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            if let enclosing = candidate.enclosingScrollView {
                return enclosing
            }
            current = candidate.superview
        }
        return nil
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: QuartzViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var selectedDate: Date
    let wheelScrollTarget: CalendarWheelScrollTarget?
    @State private var centerTrigger = 0

    @State private var updateTask: Task<Void, Never>? = nil
    @State private var isPendingUpdate = false

    init(selectedDate: Binding<Date>, wheelScrollTarget: CalendarWheelScrollTarget? = nil) {
        self._selectedDate = selectedDate
        self.wheelScrollTarget = wheelScrollTarget
    }

    var body: some View {
        VStack(spacing: -12) {
            WheelPicker(
                selectedDate: $selectedDate,
                config: Config(),
                centerTrigger: centerTrigger,
                externalScrollTarget: wheelScrollTarget
            )
                .offset(y: -7)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white, location: 0.07),
                            .init(color: .white, location: 0.93),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

            let filteredEvents = EventListView.filteredEvents(events: calendarManager.events)

            if isPendingUpdate {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                EventListView(events: calendarManager.events)
                    .padding(.leading, -2)
                    .padding(.trailing, -2)
                    .padding(.bottom, -22)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPendingUpdate)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: calendarManager.events.map(\.id))
        .frame(maxHeight: .infinity)
        .onChange(of: selectedDate) { _, newValue in
            isPendingUpdate = true
            updateTask?.cancel()
            updateTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                await calendarManager.updateCurrentDate(newValue)
                isPendingUpdate = false
            }
        }
        .onAppear {
            let today = Date.now
            if !Calendar.current.isDate(selectedDate, inSameDayAs: today) {
                selectedDate = today
            }
            centerTrigger += 1
            Task {
                await calendarManager.updateCurrentDate(today)
            }
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        Text("No events")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -8)
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    private let topFadeHeight: CGFloat = 16
    private let eventSpacing: CGFloat = 4
    private let bottomScrollBreathingRoom: CGFloat = 16

    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type { return !completed || !Defaults[.hideCompletedReminders] }
            }
            if event.isAllDay && Defaults[.hideAllDayEvents] { return false }
            return true
        }
    }

    private var filteredEvents: [EventModel] { Self.filteredEvents(events: events) }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: eventSpacing) {
                ForEach(filteredEvents) { event in
                    Button {
                        if let url = event.calendarAppURL() { openURL(url) }
                    } label: {
                        eventRow(event)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, bottomScrollBreathingRoom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollClipDisabled(true)
        .scrollIndicators(.never)
        .background(CalendarEventScrollConfigurator())
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topFadeHeight)

                Color.white
            }
        }
        .padding(.top, -8)
        .zIndex(1)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type { isCompleted = completed } else { isCompleted = false }
            return AnyView(
                HStack(spacing: 6) {
                    ReminderToggle(isOn: Binding(get: { isCompleted }, set: { newValue in
                        Task { await calendarManager.setReminderCompleted(reminderID: event.id, completed: newValue) }
                    }), color: calendarAccentColor(event.calendar.color))
                    Text(event.title)
                        .font(.system(size: 11.0))
                        .foregroundColor(.white)
                        .lineLimit(showFullEventTitles ? nil : 1)
                    Spacer()
                    Text(event.isAllDay ? "All-day" : "")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.vertical, 9)
                .padding(.trailing, 9)
                .padding(.leading, 10.5)
                .background(eventBackground(Color.white.opacity(0.12), cornerRadius: 10))
                .cornerRadius(10)
                .overlay(eventLiquidGlassReadabilityOverlay(cornerRadius: 10))
                .opacity(isCompleted ? 0.4 : 1.0)
            )
        } else {
            let eventColor = calendarAccentColor(event.calendar.color)
            let isBirthday = event.calendar.isBirthday
            let isHoliday = event.calendar.isHoliday
            let usesSpecialEventStyle = isBirthday || isHoliday || event.isAllDay
            let eventCornerRadius: CGFloat = usesSpecialEventStyle ? 999 : 10

            return AnyView(
                HStack(spacing: 6) {
                    if usesSpecialEventStyle {
                        ZStack {
                            Circle()
                                .fill(eventColor)
                                .frame(width: 14, height: 14)
                            Image(systemName: specialEventIconName(for: event, isBirthday: isBirthday, isHoliday: isHoliday))
                                .font(.system(size: 9, weight: .bold))
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    } else {
                        Rectangle()
                            .fill(eventColor)
                            .frame(width: 2.5)
                            .cornerRadius(2)
                            .padding(.vertical, 6)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 11.0))
                            .fontWeight(.regular)
                            .foregroundColor(eventTitleColor(eventColor, usesSpecialEventStyle: usesSpecialEventStyle))
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if !usesSpecialEventStyle {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.system(size: 9))
                                    .foregroundColor(eventSecondaryTextColor(eventColor))
                            } else {
                                let timeString = event.start.formatted(date: .omitted, time: .shortened) + "-" + event.end.formatted(date: .omitted, time: .shortened)
                                Text(timeString)
                                    .font(.system(size: 9))
                                    .tracking(-0.1)
                                    .foregroundColor(eventSecondaryTextColor(eventColor))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6.5)
                .background(eventBackground(eventColor.opacity(0.28), cornerRadius: eventCornerRadius))
                .cornerRadius(eventCornerRadius)
                .overlay(eventLiquidGlassReadabilityOverlay(cornerRadius: eventCornerRadius))
                .opacity(1.0)
            )
        }
    }

    private func eventBackground(_ fill: Color, cornerRadius: CGFloat) -> some View {
        ZStack {
            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
        }
    }

    private func eventLiquidGlassReadabilityOverlay(cornerRadius: CGFloat) -> some View {
        Group {
            if pageUseLiquidGlassBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .allowsHitTesting(false)
            }
        }
    }

    private func eventTitleColor(_ eventColor: Color, usesSpecialEventStyle: Bool) -> Color {
        if pageUseLiquidGlassBackground && !usesSpecialEventStyle {
            return eventColor.opacity(1.0)
        }
        return eventColor
    }

    private func eventSecondaryTextColor(_ eventColor: Color) -> Color {
        eventColor.opacity(pageUseLiquidGlassBackground ? 0.95 : 0.8)
    }

    private func calendarAccentColor(_ nsColor: NSColor) -> Color {
        guard let color = nsColor.usingColorSpace(.sRGB) else {
            return Color(nsColor).opacity(1)
        }

        return Color(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            opacity: 1.0
        )
    }

    private func specialEventIconName(for event: EventModel, isBirthday: Bool, isHoliday: Bool) -> String {
        if isBirthday { return "gift.fill" }
        if isHoliday { return "star.fill" }
        if event.isAllDay { return "calendar" }
        return "calendar"
    }
}

private struct CalendarEventScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(from: nsView)
    }

    private func configure(from view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = findScrollView(startingAt: view) else { return }
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        }
    }

    private func findScrollView(startingAt view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            if let enclosing = candidate.enclosingScrollView {
                return enclosing
            }
            current = candidate.superview
        }
        return nil
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color
    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 12, height: 12)
                if isOn { Circle().fill(color).frame(width: 6, height: 6) }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CalendarView(selectedDate: .constant(Date()), wheelScrollTarget: CalendarWheelScrollTarget())
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(QuartzViewModel())
}
