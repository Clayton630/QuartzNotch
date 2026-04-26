import Defaults
import AppKit
import SwiftUI

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 2
    var showsText: Bool = true
}

struct WheelPicker: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    @State private var containerWidth: CGFloat = 0
    let config: Config
    let centerTrigger: Int

    private let itemWidth: CGFloat = 30
    private let selectionSpring = Animation.spring(response: 0.32, dampingFraction: 0.72)

    private var sidePadding: CGFloat {
        containerWidth > itemWidth ? (containerWidth - itemWidth) / 2 : 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: config.spacing) {
                    ForEach(0..<totalDateItems(), id: \.self) { index in
                        let date = dateForItemIndex(index: index)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation(selectionSpring) {
                                scrollPosition = index
                            }
                        }
                    }
                }
                .frame(height: 60)
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        guard containerWidth > 0 else { return }
                        let stride = itemWidth + config.spacing
                        let distanceDuCentre = value.location.x - (containerWidth / 2)
                        let indexOffset = Int(round(distanceDuCentre / stride))
                        let currentIndex = scrollPosition ?? indexForDate(selectedDate)
                        let targetIndex = currentIndex + indexOffset
                        if targetIndex >= 0 && targetIndex < totalDateItems() {
                            let targetDate = dateForItemIndex(index: targetIndex)
                            if !Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                                selectedDate = targetDate
                                byClick = true
                                withAnimation(selectionSpring) {
                                    scrollPosition = targetIndex
                                }
                            }
                        }
                    }
            )
            .contentMargins(.horizontal, sidePadding, for: .scrollContent)
            .sensoryFeedback(.alignment, trigger: haptics)
            .onChange(of: scrollPosition) { _, newValue in
                if byClick {
                    if newValue == indexForDate(selectedDate) { byClick = false }
                    return
                }
                guard let id = newValue, (0..<totalDateItems()).contains(id) else { return }
                let date = dateForItemIndex(index: id)
                guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
                selectedDate = date
                if Defaults[.enableHaptics] { haptics.toggle() }
            }
            .onChange(of: selectedDate) { _, newValue in
                guard !byClick else { return }
                let target = indexForDate(newValue)
                guard scrollPosition != target else { return }
                withAnimation(selectionSpring) { scrollPosition = target }
            }
            .onChange(of: containerWidth) { _, _ in
                Task { @MainActor in proxy.scrollTo(indexForDate(selectedDate), anchor: .center) }
            }
            .onAppear {
                Task { @MainActor in proxy.scrollTo(indexForDate(selectedDate), anchor: .center) }
            }
            .onChange(of: centerTrigger) { _, _ in
                Task { @MainActor in proxy.scrollTo(indexForDate(selectedDate), anchor: .center) }
            }
        }
        .frame(height: 60)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        }
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        DayCell(date: date, isSelected: isSelected, isToday: Calendar.current.isDateInToday(date))
            .onTapGesture { onClick() }
            .id(id)
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

struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var selectedDate: Date
    @State private var centerTrigger = 0

    @State private var updateTask: Task<Void, Never>? = nil
    @State private var isPendingUpdate = false

    var body: some View {
        VStack(spacing: -12) {
            WheelPicker(selectedDate: $selectedDate, config: Config(), centerTrigger: centerTrigger)
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
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
                centerTrigger += 1
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
            LazyVStack(alignment: .leading, spacing: 4) {
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
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.never)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                Color.white
            }
        }
        .padding(.top, -8)
        .zIndex(-1)
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
    CalendarView(selectedDate: .constant(Date()))
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
