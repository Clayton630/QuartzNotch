
import AppKit
import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

extension Notification.Name {
    static let settingsSearchDidEnd = Notification.Name("settingsSearchDidEnd")
}

struct SettingsView: View {
    fileprivate enum SettingsTab: String, CaseIterable, Identifiable {
        case basics = "General"
        case interface = "Layout and style"
        case media = "Media"
        case lockScreen = "Lock Screen"
        case activities = "Live Activities"
        case calendar = "Calendar"
        case sharing = "Shelf and sharing"
        case controls = "HUD and shortcuts"
        case advanced = "Advanced"
        case about = "About"

        var id: String { rawValue }

        var label: (title: String, systemImage: String) {
            switch self {
            case .basics: return ("General", "gear")
                case .interface: return ("Layout and style", "rectangle.topthird.inset.filled")
            case .media: return ("Media", "play.laptopcomputer")
            case .lockScreen: return ("Lock Screen", "lock.fill")
            case .activities: return ("Live Activities", "sparkles")
            case .calendar: return ("Calendar", "calendar")
            case .sharing: return ("Shelf and sharing", "document.fill")
            case .controls: return ("HUD and shortcuts", "keyboard.macwindow")
            case .advanced: return ("Advanced", "gearshape.2.fill")
            case .about: return ("About", "info.circle")
            }
        }

        var searchTerms: [String] {
            switch self {
            case .basics:
                return [
                    "general", "app", "displays", "window size", "interaction", "gestures", "quit",
                    "show menu bar icon", "launch at login", "show on all displays", "preferred display",
                    "automatically switch displays", "notch height on notch displays", "match real notch height",
                    "match menu bar height", "custom height", "notch height on non-notch displays",
                    "open notch on hover", "enable haptic feedback", "remember last tab", "hover delay", "camera preview click", "quick camera click", "capture photo",
                    "enable gestures", "close gesture", "gesture sensitivity", "quit quartznotch"
                ]
            case .interface:
                return [
                    "ui", "pages", "toolbar", "dots", "background style", "page order", "shelf conditionally",
                    "show notch toolbar", "show settings icon", "show calendar button", "show battery indicator",
                    "battery percentage", "power status icons", "quick camera",
                    "show page dots", "classic", "semi liquid glass", "semi liquid glass", "always show", "show conditionally",
                    "smart reveal", "disabled", "media controls", "shelf share", "timers clipboard"
                ]
            case .media:
                return [
                    "media", "player", "music", "controls", "lyrics", "visualizer", "playback source",
                    "media mode", "system wide", "music only", "show sneak peek on playback changes",
                    "media inactivity timeout", "full screen behavior", "hide for all apps",
                    "hide for media app only", "never hide", "show lyrics below player",
                    "colored spectrogram", "player tinting", "custom visualizer",
                    "selected animation", "visualizer library", "speed", "player appearance", "player controls"
                ]
            case .lockScreen:
                return [
                    "lock screen", "media player", "timers", "unlock", "widgets", "show quartznotch on the lock screen",
                    "show media player", "show timers", "show lock unlock live activity", "presence", "content"
                ]
            case .activities:
                return [
                    "live activities", "battery", "bluetooth", "now playing", "downloads", "battery live activity",
                    "bluetooth live activity", "timer live activity", "file tray live activity", "now playing live activity",
                    "system event indicator", "popups", "compact mode", "closed activity", "full disk access",
                    "charging state", "shelf content", "focus mode", "timer", "mirror clock app timer",
                    "timer ringtone", "clock default", "radial", "radar", "alarm", "beacon", "bell tower",
                    "chimes", "cosmic", "ripples", "sencha", "uplift", "macos alert sound",
                    "show cool face animation while inactive", "inactive"
                ]
            case .calendar:
                return [
                    "calendar", "reminders", "events", "show calendar", "hide completed reminders",
                    "hide all-day events",
                    "calendars", "reminder access", "calendar access", "display"
                ]
            case .sharing:
                return [
                    "shelf", "sharing", "share", "drag", "drop", "quick share", "open shelf by default if items are present",
                    "expanded drag detection area", "copy items on drag", "remove from shelf after dragging",
                    "quick share service", "currently selected", "files dropped on the shelf will be shared via this service",
                    "shelf behavior"
                ]
            case .controls:
                return [
                    "hud", "shortcuts", "keyboard shortcuts", "volume", "brightness", "replace system hud",
                    "request accessibility",
                    "enable glowing effect", "tint progress bar with accent color", "show hud in open notch",
                    "show percentage", "hud style", "inline", "toggle sneak peek", "toggle notch open"
                ]
            case .advanced:
                return [
                    "advanced", "accent", "debug", "preview", "privacy", "capture", "rendering", "accent color",
                    "system", "custom", "using system accent", "color presets", "pick a color",
                    "enable window shadow", "corner radius scaling", "disable liquid glass",
                    "window rendering", "hide on screen capture", "app icon", "language", "app language",
                    "system language"
                ]
            case .about:
                return ["about", "version", "updates", "github", "release name", "version info", "check for updates"]
            }
        }

        var searchItems: [String] {
            switch self {
            case .basics:
                return [
                    "Show menu bar icon",
                    "Launch at login",
                    "Show on all displays",
                    "Preferred display",
                    "Automatically switch displays",
                    "Notch height on notch displays",
                    "Match real notch height",
                    "Match menu bar height",
                    "Custom height",
                    "Notch height on non-notch displays",
                    "Open notch on hover",
                    "Enable haptic feedback",
                    "Remember last tab",
                    "Hover delay",
                    "Camera preview click",
                    "Enable gestures",
                    "Close gesture",
                    "Gesture sensitivity",
                    "Quit QuartzNotch"
                ]
            case .interface:
                return [
                    "Show notch toolbar",
                    "Settings icon",
                    "Calendar toggle",
                    "Battery indicator",
                    "Battery percentage",
                    "Power status icons",
                    "Quick camera",
                    "Always show page dots",
                    "Background style",
                    "Classic",
                    "Semi liquid glass",
                    "Media controls",
                    "Shelf + Share",
                    "Timers + Clipboard",
                    "Always show",
                    "Smart reveal",
                    "Disabled"
                ]
            case .media:
                return [
                    "Media mode",
                    "Show sneak peek on playback changes",
                    "Media inactivity timeout",
                    "Full screen behavior",
                    "Hide for all apps",
                    "Hide for media app only",
                    "Never hide",
                    "Show lyrics below player",
                    "Colored spectrogram",
                    "Player tinting",
                    "Slider color",
                    "Custom visualizer",
                    "Selected animation",
                    "Add new visualizer",
                    "Speed"
                ]
            case .lockScreen:
                return [
                    "Show QuartzNotch on the lock screen",
                    "Show media player",
                    "Show timers",
                    "Show lock / unlock live activity"
                ]
            case .activities:
                return [
                    "Charging state",
                    "Shelf content",
                    "Bluetooth",
                    "Focus mode",
                    "Timer",
                    "Mirror Clock app timer",
                    "Timer ringtone",
                    "Clock default",
                    "Radial",
                    "Radar",
                    "Alarm",
                    "Beacon",
                    "Bell Tower",
                    "Chimes",
                    "Cosmic",
                    "Ripples",
                    "Sencha",
                    "Uplift",
                    "macOS alert sound",
                    "Now playing",
                    "Show cool face animation while inactive"
                ]
            case .calendar:
                return [
                    "Show calendar",
                    "Hide completed reminders",
                    "Hide all-day events"
                ]
            case .sharing:
                return [
                    "Open shelf by default if items are present",
                    "Expanded drag detection area",
                    "Copy items on drag",
                    "Remove from shelf after dragging",
                    "Quick Share Service"
                ]
            case .controls:
                return [
                    "Replace system HUD",
                    "Request Accessibility",
                    "Enable glowing effect",
                    "Tint progress bar with accent color",
                    "Show HUD in open notch",
                    "Show percentage",
                    "HUD style",
                    "Toggle Sneak Peek",
                    "Toggle Notch Open"
                ]
            case .advanced:
                return [
                    "Accent color",
                    "System",
                    "Custom",
                    "Using System Accent",
                    "Color Presets",
                    "Pick a Color",
                    "Enable window shadow",
                    "Corner radius scaling",
                    "Disable Liquid Glass",
                    "Hide on screen capture",
                    "App icon"
                ]
            case .about:
                return [
                    "Release name",
                    "Version",
                    "Check for Updates",
                    "GitHub"
                ]
            }
        }

        var iconGradientColors: (start: Color, mid: Color, end: Color, symbolTop: Color) {
            switch self {
            case .basics:
                return (
                    Color(red: 0.68, green: 0.69, blue: 0.71),
                    Color(red: 0.61, green: 0.62, blue: 0.64),
                    Color(red: 0.54, green: 0.55, blue: 0.57),
                    Color(red: 0.93, green: 0.93, blue: 0.95)
                )
            case .interface:
                return (
                    Color(red: 0.35, green: 0.67, blue: 0.94),
                    Color(red: 0.28, green: 0.60, blue: 0.92),
                    Color(red: 0.21, green: 0.51, blue: 0.89),
                    Color(red: 0.91, green: 0.93, blue: 0.96)
                )
            case .media:
                return (
                    Color(red: 0.94, green: 0.50, blue: 0.65),
                    Color(red: 0.90, green: 0.41, blue: 0.55),
                    Color(red: 0.84, green: 0.28, blue: 0.42),
                    Color(red: 0.95, green: 0.92, blue: 0.93)
                )
            case .lockScreen:
                return (
                    Color(red: 0.58, green: 0.50, blue: 0.94),
                    Color(red: 0.49, green: 0.42, blue: 0.89),
                    Color(red: 0.41, green: 0.35, blue: 0.81),
                    Color(red: 0.93, green: 0.91, blue: 0.96)
                )
            case .activities:
                return (
                    Color(red: 0.95, green: 0.71, blue: 0.33),
                    Color(red: 0.92, green: 0.64, blue: 0.29),
                    Color(red: 0.89, green: 0.58, blue: 0.23),
                    Color(red: 0.95, green: 0.94, blue: 0.89)
                )
            case .calendar:
                return (
                    Color(red: 0.95, green: 0.52, blue: 0.44),
                    Color(red: 0.91, green: 0.44, blue: 0.38),
                    Color(red: 0.86, green: 0.29, blue: 0.25),
                    Color(red: 0.95, green: 0.92, blue: 0.91)
                )
            case .sharing:
                return (
                    Color(red: 0.37, green: 0.69, blue: 0.94),
                    Color(red: 0.30, green: 0.62, blue: 0.92),
                    Color(red: 0.22, green: 0.53, blue: 0.89),
                    Color(red: 0.91, green: 0.93, blue: 0.96)
                )
            case .controls:
                return (
                    Color(red: 0.45, green: 0.78, blue: 0.93),
                    Color(red: 0.35, green: 0.70, blue: 0.88),
                    Color(red: 0.22, green: 0.62, blue: 0.80),
                    Color(red: 0.91, green: 0.94, blue: 0.95)
                )
            case .advanced:
                return (
                    Color(red: 0.68, green: 0.69, blue: 0.71),
                    Color(red: 0.61, green: 0.62, blue: 0.64),
                    Color(red: 0.54, green: 0.55, blue: 0.57),
                    Color(red: 0.93, green: 0.93, blue: 0.95)
                )
            case .about:
                return (
                    Color(red: 0.68, green: 0.69, blue: 0.71),
                    Color(red: 0.61, green: 0.62, blue: 0.64),
                    Color(red: 0.54, green: 0.55, blue: 0.57),
                    Color(red: 0.93, green: 0.93, blue: 0.95)
                )
            }
        }
    }

    @State private var selectedTab: SettingsTab = .basics
    @State private var searchText = ""
    @State private var selectedSearchResult: SettingsSearchResult?
    @State private var sidebarRefreshID = UUID()
    @State private var currentAccentColor: Color = .controlAccent
    @State private var accentColorUpdateTrigger = UUID()
    @State private var pendingAccentRefreshTask: Task<Void, Never>?
    @State private var isColorPanelVisible = false

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsSearchField(text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if isSearching {
                    if searchResultSections.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 46, weight: .regular))
                                .foregroundStyle(Color.secondary.opacity(0.65))

                            VStack(spacing: 8) {
                                Text("No results for “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .multilineTextAlignment(.center)

                                Text("Check the spelling or start a new search.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(searchResultSections) { section in
                                    VStack(alignment: .leading, spacing: 6) {
                                        SettingsSearchSectionHeader(tab: section.tab)

                                        ForEach(section.items, id: \.self) { item in
                                            let isSelected = selectedSearchResult == SettingsSearchResult(tab: section.tab, item: item)
                                            Button {
                                                selectedTab = section.tab
                                                selectedSearchResult = SettingsSearchResult(tab: section.tab, item: item)
                                            } label: {
                                                Text(NSLocalizedString(item, comment: ""))
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundStyle(isSelected ? Color.white : .primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .multilineTextAlignment(.leading)
                                                    .padding(.vertical, 4)
                                                    .padding(.horizontal, 10)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(
                                                                isSelected
                                                                ? Color.effectiveAccentBackground
                                                                : .clear
                                                            )
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                    }
                } else {
                    SettingsSidebarList(
                        tabs: SettingsTab.allCases,
                        selection: $selectedTab
                    )
                    .id(sidebarRefreshID)
                }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            detailView(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(currentAccentColor)
        .accentColor(currentAccentColor)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            currentAccentColor = .controlAccent
            pendingAccentRefreshTask?.cancel()

            if isColorPanelVisible || NSColorPanel.shared.isVisible {
                return
            }

            pendingAccentRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                accentColorUpdateTrigger = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: NSColorPanel.shared)) { _ in
            isColorPanelVisible = true
            pendingAccentRefreshTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: NSColorPanel.shared)) { _ in
            isColorPanelVisible = false
            currentAccentColor = .controlAccent
            pendingAccentRefreshTask?.cancel()
            pendingAccentRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                accentColorUpdateTrigger = UUID()
            }
        }
        .onChange(of: searchText) { _, _ in
            if !isSearching {
                selectedSearchResult = nil
                sidebarRefreshID = UUID()
                NotificationCenter.default.post(name: .settingsSearchDidEnd, object: nil)
                return
            }

            guard let selectedSearchResult else { return }
            let resultStillVisible = searchResultSections.contains {
                $0.tab == selectedSearchResult.tab && $0.items.contains(selectedSearchResult.item)
            }
            if !resultStillVisible {
                self.selectedSearchResult = nil
            }
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var searchResultSections: [SettingsSearchSection] {
        guard isSearching else { return [] }

        return SettingsTab.allCases.compactMap { tab in
            let matchingItems = tab.searchItems.filter {
                $0.localizedLowercase.contains(normalizedSearchText)
                    || NSLocalizedString($0, comment: "").localizedLowercase.contains(normalizedSearchText)
            }
            let matchesCategory = tab.label.title.localizedLowercase.contains(normalizedSearchText)
                || NSLocalizedString(tab.label.title, comment: "").localizedLowercase.contains(normalizedSearchText)
                || tab.searchTerms.contains(where: { $0.localizedLowercase.contains(normalizedSearchText) })

            let items = matchingItems.isEmpty && matchesCategory ? tab.searchItems : matchingItems
            let deduplicatedItems = items.reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }

            guard !deduplicatedItems.isEmpty else { return nil }
            return SettingsSearchSection(tab: tab, items: deduplicatedItems)
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .basics:
            GeneralSettings()
        case .interface:
            InterfaceSettings()
        case .media:
            Media()
        case .lockScreen:
            LockScreenSettings()
        case .activities:
            LiveActivities()
        case .calendar:
            CalendarSettings()
        case .sharing:
            Shelf()
        case .controls:
            HUD()
        case .advanced:
            Advanced()
        case .about:
            if let controller = updaterController {
                About(updaterController: controller)
            } else {
                About(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false,
                        updaterDelegate: nil,
                        userDriverDelegate: nil))
            }
        }
    }
}

private struct SettingsSearchResult: Equatable {
    let tab: SettingsView.SettingsTab
    let item: String
}

private struct AccentFormRefresh: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    fileprivate func accentFormRefresh() -> some View {
        modifier(AccentFormRefresh())
    }
}

private struct SettingsSearchSection: Identifiable {
    let tab: SettingsView.SettingsTab
    let items: [String]

    var id: String { tab.id }
}

private struct SettingsSidebarList: NSViewRepresentable {
    let tabs: [SettingsView.SettingsTab]
    @Binding var selection: SettingsView.SettingsTab
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ContainerView {
        let container = ContainerView()
        context.coordinator.attach(to: container)
        return container
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(tabs: tabs, selection: selection)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SettingsSidebarList
        private weak var tableView: SidebarTableView?
        private var tabs: [SettingsView.SettingsTab] = []
        private var selectedTab: SettingsView.SettingsTab
        private var visuallySelectedTab: SettingsView.SettingsTab?
        private var previewedRow: Int?

        init(parent: SettingsSidebarList) {
            self.parent = parent
            self.selectedTab = parent.selection
        }

        func attach(to container: ContainerView) {
            tableView = container.sidebarTableView
            container.sidebarTableView.dataSource = self
            container.sidebarTableView.delegate = self
            container.sidebarTableView.previewSelectionHandler = { [weak self] row in
                self?.previewSelection(row: row)
            }
            container.sidebarTableView.commitSelectionHandler = { [weak self] row in
                self?.commitSelection(row: row)
            }
            container.sidebarTableView.cancelPreviewHandler = { [weak self] in
                self?.cancelPreview()
            }
            update(tabs: parent.tabs, selection: parent.selection)
        }

        func update(tabs: [SettingsView.SettingsTab], selection: SettingsView.SettingsTab) {
            self.tabs = tabs
            selectedTab = selection
            if let visuallySelectedTab, visuallySelectedTab != selection {
                self.visuallySelectedTab = nil
            }
            tableView?.reloadData()
            syncSelection(to: selection)
        }

        private func syncSelection(to selection: SettingsView.SettingsTab) {
            guard let tableView else { return }
            let targetRow = tabs.firstIndex(of: selection) ?? 0
            tableView.deselectAll(nil)
            tableView.scrollRowToVisible(targetRow)
            tableView.refreshSelectionAppearance()
        }

        private func previewSelection(row: Int) {
            guard let tableView, tabs.indices.contains(row), previewedRow != row else { return }
            previewedRow = row
            tableView.reloadData()
        }

        private func commitSelection(row: Int) {
            guard tabs.indices.contains(row) else { return }
            selectedTab = tabs[row]
            visuallySelectedTab = tabs[row]
            previewedRow = nil
            parent.selection = tabs[row]
            tableView?.reloadData()
        }

        private func cancelPreview() {
            guard previewedRow != nil else { return }
            previewedRow = nil
            tableView?.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            tabs.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            37
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SidebarRowView()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("SettingsSidebarCell")
            let cell =
                (tableView.makeView(withIdentifier: identifier, owner: nil) as? SidebarCategoryCellView)
                ?? SidebarCategoryCellView(identifier: identifier)
            let selectedRow = previewedRow ?? visuallySelectedTab.flatMap { tabs.firstIndex(of: $0) }
            cell.configure(with: tabs[row], isSelected: row == selectedRow)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            tableView?.deselectAll(nil)
        }
    }

    private final class SidebarRowView: NSTableRowView {
        override var isSelected: Bool {
            didSet { needsDisplay = true }
        }

        override var interiorBackgroundStyle: NSView.BackgroundStyle {
            isSelected ? .emphasized : .normal
        }

        override func drawSelection(in dirtyRect: NSRect) {}

        override func drawBackground(in dirtyRect: NSRect) {
            super.drawBackground(in: dirtyRect)
            if isSelected {
                let insetRect = bounds.insetBy(dx: 11, dy: 2.3)
                let path = NSBezierPath(roundedRect: insetRect, xRadius: 7, yRadius: 7)
                NSColor.effectiveControlAccent.setFill()
                path.fill()
            }
        }
    }

    final class SidebarTableView: NSTableView {
        var previewSelectionHandler: ((Int) -> Void)?
        var commitSelectionHandler: ((Int) -> Void)?
        var cancelPreviewHandler: (() -> Void)?

        override func highlightSelection(inClipRect clipRect: NSRect) {}

        func refreshSelectionAppearance() {
            setNeedsDisplay(bounds)
            guard selectedRow >= 0 else { return }
            rowView(atRow: selectedRow, makeIfNecessary: false)?.needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            let initialPoint = convert(event.locationInWindow, from: nil)
            let initialRow = row(at: initialPoint)
            guard initialRow >= 0 else { return }
            previewSelectionHandler?(initialRow)

            while let nextEvent = window?.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) {
                switch nextEvent.type {
                case .leftMouseDragged:
                    continue
                case .leftMouseUp:
                    let releasePoint = convert(nextEvent.locationInWindow, from: nil)
                    let releaseRow = row(at: releasePoint)
                    guard releaseRow == initialRow else {
                        cancelPreviewHandler?()
                        return
                    }
                    commitSelectionHandler?(releaseRow)
                    return
                default:
                    cancelPreviewHandler?()
                    return
                }
            }
        }
    }

    final class ContainerView: NSView {
        let scrollView = NSScrollView()
        fileprivate let sidebarTableView = SidebarTableView()
        private var accentObserver: NSObjectProtocol?
        private var searchEndObserver: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            accentObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AccentColorChanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.sidebarTableView.needsDisplay = true
            }

            searchEndObserver = NotificationCenter.default.addObserver(
                forName: .settingsSearchDidEnd,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.window else { return }
                    window.endEditing(for: nil)
                    window.makeFirstResponder(nil)
                    window.makeFirstResponder(self.sidebarTableView)
                    self.sidebarTableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<self.sidebarTableView.numberOfRows))
                    self.sidebarTableView.refreshSelectionAppearance()
                    self.needsDisplay = true
                    self.displayIfNeeded()
                }
            }

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SettingsSidebarColumn"))
            column.resizingMask = .autoresizingMask

            sidebarTableView.addTableColumn(column)
            sidebarTableView.headerView = nil
            sidebarTableView.focusRingType = .none
            sidebarTableView.allowsColumnReordering = false
            sidebarTableView.allowsColumnResizing = false
            sidebarTableView.allowsEmptySelection = true
            sidebarTableView.allowsMultipleSelection = false
            sidebarTableView.gridStyleMask = []
            sidebarTableView.rowSizeStyle = .custom
            sidebarTableView.selectionHighlightStyle = .none
            sidebarTableView.deselectAll(nil)

            scrollView.borderType = .noBorder
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.documentView = sidebarTableView
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            addSubview(scrollView)

            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        deinit {
            if let accentObserver {
                NotificationCenter.default.removeObserver(accentObserver)
            }
            if let searchEndObserver {
                NotificationCenter.default.removeObserver(searchEndObserver)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class SidebarCategoryCellView: NSTableCellView {
        private let hostingView: NSHostingView<SettingsCategoryRow>

        init(identifier: NSUserInterfaceItemIdentifier) {
            self.hostingView = NSHostingView(rootView: SettingsCategoryRow(tab: .basics, isSelected: false))
            super.init(frame: .zero)
            self.identifier = identifier
            wantsLayer = false

            hostingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        func configure(with tab: SettingsView.SettingsTab, isSelected: Bool) {
            hostingView.rootView = SettingsCategoryRow(tab: tab, isSelected: isSelected)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

private struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> SidebarSearchFieldContainer {
        let container = SidebarSearchFieldContainer()
        context.coordinator.container = container
        container.searchField.placeholderString = NSLocalizedString("Search", comment: "")
        container.searchField.controlSize = .large
        container.searchField.sendsSearchStringImmediately = true
        container.searchField.focusRingType = .default
        container.searchField.delegate = context.coordinator
        container.searchField.stringValue = text
        return container
    }

    func updateNSView(_ nsView: SidebarSearchFieldContainer, context: Context) {
        context.coordinator.container = nsView
        if nsView.searchField.stringValue != text {
            nsView.searchField.stringValue = text
        }
    }

    final class SidebarSearchFieldContainer: NSView {
        let searchField = NSSearchField(frame: .zero)
        private var accentObserver: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false

            searchField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(searchField)

            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
                searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
                searchField.topAnchor.constraint(equalTo: topAnchor),
                searchField.bottomAnchor.constraint(equalTo: bottomAnchor),
                heightAnchor.constraint(equalToConstant: 44)
            ])

            accentObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AccentColorChanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.searchField.noteFocusRingMaskChanged()
                self?.searchField.needsDisplay = true
                self?.needsDisplay = true
            }
        }

        deinit {
            if let accentObserver {
                NotificationCenter.default.removeObserver(accentObserver)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 44)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        weak var container: SidebarSearchFieldContainer?

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

private struct SettingsSearchSectionHeader: View {
    let tab: SettingsView.SettingsTab

    var body: some View {
        HStack(spacing: 8) {
            SettingsCategoryRow(tab: tab, isSelected: false)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Interface

struct InterfaceSettings: View {
    private enum BackgroundStyle: String, CaseIterable, Identifiable {
        case classic = "Classic"
        case semiLiquidGlass = "Semi Liquid Glass"

        var id: String { rawValue }
    }

    @Default(.toolbarEnabled) private var toolbarEnabled
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.pageOrder) private var storedPageOrder
    @Default(.pageUseLiquidGlassBackground) private var pageUseLiquidGlassBackground
    @ObservedObject private var coordinator = QuartzViewCoordinator.shared
    @State private var orderedPages: [NotchViews] = configuredNotchViewOrder()
    @State private var pageVisibilityModes: [NotchViews: NotchPageVisibilityMode] =
        Dictionary(uniqueKeysWithValues: configuredNotchViewOrder().map { ($0, $0.visibilityMode) })
    @State private var draggingPage: NotchViews?
    @State private var dragTranslationY: CGFloat = 0
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?

    private let pageCardHeight: CGFloat = 38
    private let pageCardSpacing: CGFloat = 8

    private var backgroundStyleBinding: Binding<BackgroundStyle> {
        Binding(
            get: { pageUseLiquidGlassBackground ? .semiLiquidGlass : .classic },
            set: { pageUseLiquidGlassBackground = ($0 == .semiLiquidGlass) }
        )
    }

    private var pageCardStride: CGFloat {
        pageCardHeight + pageCardSpacing
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toolbar")
                            .font(.system(size: 13, weight: .semibold))
                        Text("The toolbar is a small capsule placed in the top right corner, allowing you to quickly access different controls and informations, customisable below.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                    Toggle("", isOn: $toolbarEnabled)
                        .liveAccentToggleTint()
                        .labelsHidden()
                        .tint(.controlAccent)
                        .scaleEffect(1.2)
                        .padding(.trailing, 2)
                }
                .listRowBackground(Color.effectiveAccentBackground)
            }

            Section {
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Settings icon")
                }
                .liveAccentToggleTint()

                Defaults.Toggle(key: .showCalendarToggle) {
                    Text("Calendar toggle")
                }
                .liveAccentToggleTint()

                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Battery indicator")
                }
                .liveAccentToggleTint()

                if showBatteryIndicator {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Battery percentage")
                    }
                    .liveAccentToggleTint()

                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Power status icons")
                    }
                    .liveAccentToggleTint()
                }

                Defaults.Toggle(key: .showMirror) {
                    Text("Quick camera")
                }
                .liveAccentToggleTint()
                .disabled(!hasVideoInput())
            }
            .disabled(!toolbarEnabled)

            Section {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: pageCardSpacing) {
                        ForEach(Array(orderedPages.enumerated()), id: \.element) { index, page in
                            PageOrderRow(
                                page: page,
                                index: index,
                                visibilityMode: pageVisibilityBinding(for: page),
                                onDragChanged: { translation in
                                    handlePageDragChanged(page, translation: translation)
                                },
                                onDragEnded: {
                                    finishPageDrag()
                                }
                            )
                            .frame(height: pageCardHeight)
                            .opacity(draggingPage == page ? 0 : 1)
                            .offset(y: stackOffset(for: page, at: index))
                        }
                    }

                    if let draggingPage,
                       let startIndex = dragStartIndex,
                       let dragIndex = orderedPages.firstIndex(of: draggingPage)
                    {
                        PageOrderRow(
                            page: draggingPage,
                            index: dragIndex,
                            visibilityMode: pageVisibilityBinding(for: draggingPage),
                            onDragChanged: { translation in
                                handlePageDragChanged(draggingPage, translation: translation)
                            },
                            onDragEnded: {
                                finishPageDrag()
                            }
                        )
                        .frame(height: pageCardHeight)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .offset(y: CGFloat(startIndex) * pageCardStride + dragTranslationY)
                        .zIndex(10)
                    }
                }
                .frame(height: stackHeight)

                Toggle("Show page dots", isOn: $coordinator.alwaysShowTabs)
                    .liveAccentToggleTint()

                LabeledContent("Background style") {
                    AccentMenuPicker(
                        selection: backgroundStyleBinding,
                        options: BackgroundStyle.allCases,
                        title: { $0.rawValue }
                    )
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("\"Smart reveal\" only shows the Shelf page when you are dragging files into it, or when it already contains files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentFormRefresh()
        .navigationTitle("Layout and style")
        .onAppear {
            orderedPages = configuredNotchViewOrder()
            refreshPageVisibilityModes()
        }
        .onChange(of: storedPageOrder) { _, _ in
            orderedPages = configuredNotchViewOrder()
            refreshPageVisibilityModes()
            syncCurrentViewIfNeeded()
        }
    }

    private func hasVideoInput() -> Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    private func pageVisibilityBinding(for page: NotchViews) -> Binding<NotchPageVisibilityMode> {
        Binding(
            get: { pageVisibilityMode(for: page) },
            set: { newValue in setPageVisibilityMode(for: page, to: newValue) }
        )
    }

    private func pageVisibilityMode(for page: NotchViews) -> NotchPageVisibilityMode {
        pageVisibilityModes[page] ?? page.visibilityMode
    }

    private func setPageVisibilityMode(for page: NotchViews, to newValue: NotchPageVisibilityMode) {
        var modes = pageVisibilityModes
        modes[page] = newValue

        let alwaysShownCount = modes.values.filter { $0 == .alwaysShow }.count
        if alwaysShownCount == 0,
           let fallback = orderedPages.first(where: { $0 != page && $0.supportedVisibilityModes.contains(.alwaysShow) }) {
            modes[fallback] = .alwaysShow
        }

        pageVisibilityModes = modes

        for (view, mode) in modes {
            applyPageVisibilityMode(view, mode)
        }

        syncCurrentViewIfNeeded()
    }

    private func applyPageVisibilityMode(_ page: NotchViews, _ mode: NotchPageVisibilityMode) {
        switch page {
        case .home:
            Defaults[.pageHomeEnabled] = (mode == .alwaysShow)
        case .shelf:
            Defaults[.pageShelfEnabled] = (mode == .alwaysShow)
            Defaults[.allowShelfRevealWhenPageHidden] = (mode == .showConditionally)
        case .third:
            Defaults[.pageThirdEnabled] = (mode == .alwaysShow)
        }
    }

    private func savePageOrder(_ pages: [NotchViews]) {
        let previousDefault = coordinator.preferredDefaultView(respectShelfPreference: true)
        let normalized = NotchViews.normalizedOrder(from: pages.map(\.rawValue))
        orderedPages = normalized
        storedPageOrder = normalized.map(\.rawValue)
        refreshPageVisibilityModes()
        let newDefault = coordinator.preferredDefaultView(respectShelfPreference: true)

        if !coordinator.openLastTabByDefault && coordinator.currentView == previousDefault {
            coordinator.currentView = newDefault
        }

        syncCurrentViewIfNeeded()
    }

    private func syncCurrentViewIfNeeded() {
        let enabledViews = orderedPages.filter { pageVisibilityMode(for: $0) == .alwaysShow }
        guard let firstEnabled = enabledViews.first else { return }
        guard enabledViews.contains(coordinator.currentView) else {
            coordinator.currentView = firstEnabled
            return
        }
    }

    private func refreshPageVisibilityModes() {
        pageVisibilityModes = Dictionary(
            uniqueKeysWithValues: configuredNotchViewOrder().map { ($0, $0.visibilityMode) }
        )
    }

    private var stackHeight: CGFloat {
        CGFloat(orderedPages.count) * pageCardHeight + CGFloat(max(orderedPages.count - 1, 0)) * pageCardSpacing
    }

    private func handlePageDragChanged(_ page: NotchViews, translation: CGSize) {
        if draggingPage != page {
            draggingPage = page
            dragStartIndex = orderedPages.firstIndex(of: page)
            dragTargetIndex = dragStartIndex
            dragTranslationY = 0
        }

        guard let startIndex = dragStartIndex else { return }

        dragTranslationY = translation.height

        let projectedRow = CGFloat(startIndex) + (translation.height / pageCardStride)
        let targetIndex = min(max(Int(projectedRow.rounded()), 0), orderedPages.count - 1)

        if dragTargetIndex != targetIndex {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                dragTargetIndex = targetIndex
            }
        }
    }

    private func finishPageDrag() {
        guard
            let draggingPage,
            let startIndex = dragStartIndex,
            let targetIndex = dragTargetIndex
        else {
            withAnimation(nil) { resetPageDragState() }
            return
        }

        if startIndex != targetIndex,
           let currentIndex = orderedPages.firstIndex(of: draggingPage) {
            var updatedPages = orderedPages
            updatedPages.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
            )
            savePageOrder(updatedPages)
        }

        withAnimation(nil) { resetPageDragState() }
    }

    private func resetPageDragState() {
        draggingPage = nil
        dragTranslationY = 0
        dragStartIndex = nil
        dragTargetIndex = nil
    }

    private func stackOffset(for page: NotchViews, at index: Int) -> CGFloat {
        guard
            let draggingPage,
            let startIndex = dragStartIndex,
            let targetIndex = dragTargetIndex,
            page != draggingPage
        else {
            return 0
        }

        if startIndex < targetIndex, index > startIndex, index <= targetIndex {
            return -pageCardStride
        }

        if startIndex > targetIndex, index >= targetIndex, index < startIndex {
            return pageCardStride
        }

        return 0
    }
}

private struct PageOrderRow: View {
    let page: NotchViews
    let index: Int
    @Binding var visibilityMode: NotchPageVisibilityMode
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    private var isAlwaysShownBinding: Binding<Bool> {
        Binding(
            get: { visibilityMode == .alwaysShow },
            set: { visibilityMode = $0 ? .alwaysShow : .disabled }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onDragChanged(value.translation)
                        }
                        .onEnded { _ in
                            onDragEnded()
                        }
                )

            Text(page.settingsTitle)
                .font(.body.weight(.medium))

            Spacer(minLength: 12)

            Group {
                if page == .shelf {
                    AccentMenuPicker(
                        selection: $visibilityMode,
                        options: page.supportedVisibilityModes,
                        title: { $0.displayName },
                        menuWidth: 180
                    )
                    .frame(width: 142, alignment: .trailing)
                } else {
                    Toggle("", isOn: isAlwaysShownBinding)
                        .liveAccentToggleTint()
                        .labelsHidden()
                        .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: QuartzViewModel
    @ObservedObject var coordinator = QuartzViewCoordinator.shared

    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.cameraPreviewClickAction) var cameraPreviewClickAction

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        let c = SettingsView.SettingsTab.basics.iconGradientColors
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LinearGradient(
                                colors: [c.start, c.mid, c.end],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: 52, height: 52)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        Image(systemName: "gear")
                            .font(.system(size: 35, weight: .medium))
                            .foregroundStyle(c.symbolTop)
                    }

                    Text("General")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Configure how QuartzNotch behaves, which display it appears on, and how you interact with it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.controlAccent)
                .liveAccentToggleTint()
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                    .liveAccentToggleTint()
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .liveAccentToggleTint()
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                LabeledContent("Preferred display") {
                    AccentMenuPicker(
                        selection: $coordinator.preferredScreenUUID,
                        options: [nil] + screens.map { Optional($0.uuid) },
                        title: { selection in
                            guard let selection else { return "Current Display" }
                            return screens.first(where: { $0.uuid == selection })?.name ?? "Current Display"
                        },
                        menuWidth: 220
                    )
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                    .liveAccentToggleTint()
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text("App & Displays")
            }

            Section {
                LabeledContent("Notch height on notch displays") {
                    AccentMenuPicker(
                        selection: $notchHeightMode,
                        options: [.matchRealNotchSize, .matchMenuBar, .custom],
                        title: { mode in
                            switch mode {
                            case .matchRealNotchSize: "Match real notch height"
                            case .matchMenuBar: "Match menu bar height"
                            case .custom: "Custom height"
                            }
                        },
                        menuWidth: 220
                    )
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .settingsSliderHaptics(value: notchHeight, lowerBound: 15, step: 1)
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                LabeledContent("Notch height on non-notch displays") {
                    AccentMenuPicker(
                        selection: $nonNotchHeightMode,
                        options: [.matchMenuBar, .matchRealNotchSize, .custom],
                        title: { mode in
                            switch mode {
                            case .matchMenuBar: "Match menubar height"
                            case .matchRealNotchSize: "Match real notch height"
                            case .custom: "Custom height"
                            }
                        },
                        menuWidth: 220
                    )
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .settingsSliderHaptics(value: nonNotchHeight, lowerBound: 0, step: 1)
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Window Size")
            }

            NotchBehaviour()

            gestureControls()

        }
        .accentFormRefresh()
        .navigationTitle("General")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit QuartzNotch", systemImage: "power")
                }
                .foregroundStyle(.red)
            }
        }
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
                .liveAccentToggleTint()
                .disabled(!openNotchOnHover)
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .liveAccentToggleTint()
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            NSLocalizedString(
                                Defaults[.gestureSensitivity] == 100
                                    ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low",
                                comment: ""
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .settingsSliderHaptics(value: gestureSensitivity, lowerBound: 100, step: 100)
            }
        } header: {
            HStack {
                Text("Gestures")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            .liveAccentToggleTint()
            Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
            }
            .liveAccentToggleTint()
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
                .liveAccentToggleTint()
            LabeledContent("Camera preview click") {
                AccentMenuPicker(
                    selection: $cameraPreviewClickAction,
                    options: CameraPreviewClickAction.allCases,
                    title: { $0.rawValue },
                    menuWidth: 180
                )
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsSliderHaptics(value: minimumHoverDuration, lowerBound: 0, step: 0.1)
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Interaction")
        }
    }
}

private struct SettingsCategoryRow: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            let gradient = tab.iconGradientColors
            let badgeCornerRadius: CGFloat = 5.5
            let iconSize: CGFloat =
                if tab == .basics {
                    12.85
                } else if tab == .lockScreen {
                    12.05
                } else {
                    11.5
                }

            RoundedRectangle(cornerRadius: badgeCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: gradient.start, location: 0.0),
                            .init(color: gradient.mid, location: 0.34),
                            .init(color: gradient.end, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 20.5, height: 20.5)
                .shadow(color: .black.opacity(0.18), radius: 3.4, x: 0, y: 1.4)
                .overlay {
                    Image(systemName: tab.label.systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                stops: [
                                    .init(color: gradient.symbolTop, location: 0.0),
                                    .init(color: Color.white.opacity(0.992), location: 0.62),
                                    .init(color: .white, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.07), radius: 0.45, x: 0, y: 0.35)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: badgeCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
                }

            Text(NSLocalizedString(tab.label.title, comment: ""))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.controlAccent : .clear)
                .padding(.horizontal, -2.5)
        }
    }
}


struct HUD: View {
    @EnvironmentObject var vm: QuartzViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                        .liveAccentToggleTint()
                        .labelsHidden()
                        .tint(.controlAccent)
                        .scaleEffect(1.2)
                        .padding(.trailing, 2)
                        .disabled(!accessibilityAuthorized)
                }
                .listRowBackground(Color.effectiveAccentBackground)
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.controlAccent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            Section {
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
                .liveAccentToggleTint()
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .liveAccentToggleTint()
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Open Notch")
                    customBadge(text: "Coming soon")
                }
            }
            .disabled(true)
            
            Section {
                LabeledContent("HUD style") {
                    AccentMenuPicker(
                        selection: $inlineHUD,
                        options: [false, true],
                        title: { $0 ? "Inline" : "Default" },
                        menuWidth: 150
                    )
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .liveAccentToggleTint()
            } header: {
                Text("Closed Notch")
            }
            .disabled(!Defaults[.hudReplacement])

            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek", name: .toggleSneakPeek)
                KeyboardShortcuts.Recorder("Toggle Notch Open", name: .toggleNotchOpen)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Sneak Peek temporarily shows media details below the notch. Toggle Notch Open opens or closes QuartzNotch manually.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentFormRefresh()
        .navigationTitle("HUD")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.playbackScope) var playbackScope
    @ObservedObject var coordinator = QuartzViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek

    @Default(.enableLyrics) var enableLyrics
    @Default(.enableNotchLyrics) var enableNotchLyrics
  // MARK: - Appearance (moved here)
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0


    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Playback Source")
                            .font(.system(size: 13, weight: .semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("System Wide follows macOS Now Playing (any media app).")
                            Text("Music Only follows Music, Spotify, and YouTube Music.")
                            HStack(spacing: 4) {
                                Text("YouTube Music requires:")
                                Link(
                                    "pear-devs/pear-desktop",
                                    destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                                )
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                    Spacer()
                    AccentMenuPicker(
                        selection: $playbackScope,
                        options: PlaybackScope.allCases,
                        title: { $0.rawValue },
                        menuWidth: 220,
                        controlSize: .large,
                        prominence: .emphasized
                    )
                    .fixedSize()
                    .padding(.trailing, 2)
                    .onChange(of: playbackScope) { _, _ in
                        NotificationCenter.default.post(name: .playbackScopeChanged, object: nil)
                    }
                }
                .listRowBackground(Color.effectiveAccentBackground)
            }
            
            Section {
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                    .liveAccentToggleTint()
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent {
                    AccentMenuPicker(
                        selection: $hideNotchOption,
                        options: [.always, .nowPlayingOnly, .never],
                        title: { option in
                            switch option {
                            case .always: "Hide for all apps"
                            case .nowPlayingOnly: "Hide for media app only"
                            case .never: "Never hide"
                            }
                        },
                        menuWidth: 220
                    )
                } label: {
                    HStack {
                        Text("Full screen behavior")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Playback Behavior")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableNotchLyrics) {
                    HStack {
                        Text("Show lyrics in notch player")
                        customBadge(text: "Beta")
                    }
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics on lock screen")
                        customBadge(text: "Beta")
                    }
                }
                .liveAccentToggleTint()
            } header: {
                Text("Player Controls")
            }


            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                .liveAccentToggleTint()
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                    .liveAccentToggleTint()
                Defaults.Toggle(key: .liveAudioWaveform) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live audio waveform")
                        Text("Sync notch bars to system audio (macOS 14.2+, non-sandboxed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .liveAccentToggleTint()
            } header: {
                Text("Player Appearance")
            }

            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .liveAccentToggleTint()
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        LabeledContent("Selected animation") {
                            AccentMenuPicker(
                                selection: $selectedVisualizer,
                                options: customVisualizers.map(Optional.some),
                                title: { $0?.name ?? "Selected animation" },
                                menuWidth: 220
                            )
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom Visualizer")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil
                                ? selectedListVisualizer == visualizer
                                    ? Color.effectiveAccentBackground : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(
                                    at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                                .settingsSliderHaptics(value: Double(speed), lowerBound: 0, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Visualizer Library")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accentFormRefresh()
        .navigationTitle("Media")
    }
}

struct LockScreenSettings: View {
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.liveActivityLockScreen) private var liveActivityLockScreen

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QuartzNotch on the lock screen")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Enables QuartzNotch on the lock screen and unlock screen, including the content options below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Toggle("", isOn: $showOnLockScreen)
                        .liveAccentToggleTint()
                        .labelsHidden()
                        .tint(.controlAccent)
                        .scaleEffect(1.2)
                        .padding(.trailing, 2)
                }
                .listRowBackground(Color.effectiveAccentBackground)
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Media player")
                }
                .liveAccentToggleTint()

                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text("Timers")
                }
                .liveAccentToggleTint()

                Defaults.Toggle(key: .liveActivityLockScreen) {
                    Text("Lock / unlock live activity")
                }
                .liveAccentToggleTint()
            }
            .disabled(!showOnLockScreen)
        }
        .accentFormRefresh()
        .navigationTitle("Lock Screen")
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) private var showCalendar
        @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCalendar) {
                    Text("Show calendar")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .hideCompletedReminders) {
                    Text("Hide completed reminders")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .hideAllDayEvents) {
                    Text("Hide all-day events")
                }
                .liveAccentToggleTint()
            } header: {
                Text("Display")
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus == .notDetermined {
                    Text("Calendar access is not granted yet.")
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                    Button("Grant Calendar Access") {
                        Task {
                            await calendarManager.checkCalendarAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.controlAccent)
                } else if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.controlAccent)
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                                                    }
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus == .notDetermined {
                    Text("Reminder access is not granted yet.")
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                    Button("Grant Reminder Access") {
                        Task {
                            await calendarManager.checkReminderAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.controlAccent)
                } else if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.controlAccent)
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                                                    }
                    }
                }
            }
        }
        .accentFormRefresh()
        .navigationTitle("Calendar & Reminders")
        .onAppear {
            Task {
                calendarManager.refreshCalendarAuthorizationStatus()
                calendarManager.refreshReminderAuthorizationStatus()
                if calendarManager.calendarAuthorizationStatus == .fullAccess
                    || calendarManager.reminderAuthorizationStatus == .fullAccess
                {
                    await calendarManager.reloadCalendarAndReminderLists()
                }
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack {
            Form {
                Section {
                    VStack(spacing: 0) {
                        VStack(spacing: 6) {
                            Text("β")
                                .font(.system(size: 52, weight: .semibold, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text("Beta Version")
                                .font(.title.bold())
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text("You are currently running QuartzNotch Beta 0.4.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom, 16)

                        Divider()

                        VStack(spacing: 0) {
                            HStack {
                                Text("Version")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4")
                            }
                            .padding(.vertical, 8)

                            Divider()

                            HStack {
                                Text("Channel")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Beta")
                            }
                            .padding(.vertical, 8)

                            Divider()

                            HStack {
                                Text("Build")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 92) {
                    aboutLinkButton(
                        title: "X",
                        url: "https://x.com/clay_rebirth"
                    ) {
                        Text("𝕏")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .offset(y: 1)
                    }
                    aboutLinkButton(
                        title: "Buy me a coffee",
                        url: "https://buymeacoffee.com/clayton630"
                    ) {
                        Image("BuyMeACoffee")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 38, height: 29)
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .offset(y: -1)
                    }
                    aboutLinkButton(
                        title: "GitHub",
                        url: "https://github.com/Clayton630/QuartzNotch"
                    ) {
                        Image("Github")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 22)
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(PlainButtonStyle())
            }
        }
        .overlay(alignment: .bottom) {
            Text("Made with 🫶 by Clayton")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }

    private func aboutLinkButton<Icon: View>(
        title: LocalizedStringKey,
        url: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(spacing: 5) {
                icon()
                .frame(width: 34, height: 28)
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 34)
            .contentShape(Rectangle())
        }
    }
}

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Share Service")
                            .font(.system(size: 13, weight: .semibold))

                        if let selectedProvider = selectedProvider {
                            HStack(spacing: 6) {
                                quickShareProviderIcon(selectedProvider)
                                    .frame(width: 16, height: 16)
                                Text("Currently selected: \(selectedProvider.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }

                    Spacer()

                    AccentMenuPicker(
                        selection: $quickShareProvider,
                        options: quickShareService.availableProviders.map(\.id),
                        title: { $0 },
                        menuWidth: 220,
                        controlSize: .large,
                        prominence: .emphasized,
                        leadingView: { providerID, isHovered in
                            guard let provider = quickShareService.availableProviders.first(where: { $0.id == providerID }) else {
                                return nil
                            }
                            return AnyView(
                                quickShareProviderMenuIcon(provider, isHovered: isHovered)
                                    .frame(width: 10, height: 10)
                            )
                        }
                    )
                    .fixedSize()
                    .padding(.trailing, 2)
                }
                .listRowBackground(Color.effectiveAccentBackground)
            }

            Section {
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .liveAccentToggleTint()
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                .liveAccentToggleTint()

            } header: {
                HStack {
                    Text("Shelf Behavior")
                }
            }
        }
        .accentFormRefresh()
        .navigationTitle("Shelf and Sharing")
    }

    @ViewBuilder
    private func quickShareProviderIcon(_ provider: QuickShareProvider) -> some View {
        if isAirDropProvider(provider.id) {
            Image("AirDrop")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.effectiveAccent)
        } else if let symbol = systemSymbolName(for: provider.id) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.effectiveAccent)
        } else if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .brightness(0.04)
                .colorMultiply(.effectiveAccent)
        } else if let nsImg = ProviderAppIconResolver.icon(forProviderName: provider.id) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .brightness(0.04)
                .colorMultiply(.effectiveAccent)
        } else {
            Image(systemName: "square.and.arrow.up")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.effectiveAccent)
        }
    }

    @ViewBuilder
    private func quickShareProviderMenuIcon(_ provider: QuickShareProvider, isHovered: Bool) -> some View {
        if isAirDropProvider(provider.id) {
            if let tinted = tintedAirDropMenuImage(isHovered: isHovered) {
                Image(nsImage: tinted)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isHovered ? .white : .effectiveAccent)
            }
        } else {
            quickShareProviderMenuForegroundIcon(provider, isHovered: isHovered)
        }
    }

    @ViewBuilder
    private func quickShareProviderMenuForegroundIcon(_ provider: QuickShareProvider, isHovered: Bool) -> some View {
        let tint = isHovered ? Color.white : .effectiveAccent

        if let symbol = systemSymbolName(for: provider.id) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(tint)
        } else if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .brightness(0.04)
                .colorMultiply(tint)
        } else if let nsImg = ProviderAppIconResolver.icon(forProviderName: provider.id) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .brightness(0.04)
                .colorMultiply(tint)
        } else {
            Image(systemName: "square.and.arrow.up")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(tint)
        }
    }

    private func tintedAirDropMenuImage(isHovered: Bool) -> NSImage? {
        guard let base = NSImage(named: "AirDrop") else { return nil }
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = NSSize(width: 16, height: 16)
        let output = NSImage(size: size)
        output.lockFocus()
        (isHovered ? NSColor.white : NSColor.effectiveAccent).setFill()
        let rect = NSRect(origin: .zero, size: size)
        let src = NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        let scale = min(size.width / max(src.width, 1), size.height / max(src.height, 1))
        let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
        let drawRect = NSRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        NSImage(cgImage: cg, size: src).draw(in: drawRect)
        rect.fill(using: .sourceAtop)
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func isAirDropProvider(_ providerName: String) -> Bool {
        providerName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .contains("airdrop")
    }

    private func systemSymbolName(for providerName: String) -> String? {
        let name = providerName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if name.contains("message") || name.contains("imessage") { return "message.fill" }
        if name.contains("mail") { return "envelope.fill" }
        if name.contains("notes") || name.contains("note") { return "note.text" }
        if name.contains("reminder") || name.contains("rappel") { return "list.bullet" }
        if name.contains("system share menu") { return "square.and.arrow.up" }
        return nil
    }

}


struct Advanced: View {
    @Default(.appLanguage) var appLanguage
    @Default(.cinemaMode) var cinemaMode
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.appIconChoice) var appIconChoice
    @Default(.hideFromScreenRecordingMode) var hideFromScreenRecordingMode
    @Default(.forceLiquidGlassCompatibilityFallback) var forceLiquidGlassCompatibilityFallback
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    @StateObject private var appIconPreviewMonitor = AppIconPreviewMonitor()
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Accent Color")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Use the default QuartzNotch accent color or override it with your own custom color.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                    Toggle("", isOn: $useCustomAccentColor)
                        .liveAccentToggleTint()
                        .labelsHidden()
                        .tint(.controlAccent)
                        .scaleEffect(1.2)
                        .padding(.trailing, 2)
                }
                .listRowBackground(Color.effectiveAccentBackground)

                if useCustomAccentColor {
                    HStack(spacing: 12) {
                        ForEach(PresetAccentColor.allCases) { preset in
                            AccentCircleButton(
                                isSelected: selectedPresetColor == preset,
                                color: preset.color,
                                isMulticolor: false
                            ) {
                                selectedPresetColor = preset
                                customAccentColor = preset.color
                                saveCustomColor(preset.color)
                                forceUiUpdate()
                            }
                        }
                        Spacer()
                        ColorPicker(selection: Binding(
                            get: { customAccentColor },
                            set: { newColor in
                                customAccentColor = newColor
                                selectedPresetColor = nil
                                saveCustomColorSilently(newColor)
                            }
                        ), supportsOpacity: false) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .frame(width: 28, height: 28)
                    }
                }
            }
            .onAppear {
                initializeAccentColorState()
            }
            .onChange(of: useCustomAccentColor) { _, _ in
                forceUiUpdate()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: NSColorPanel.shared)) { _ in
                guard useCustomAccentColor else { return }
                forceUiUpdate()
            }
            
            Section {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("App icon")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Choose which icon pack QuartzNotch uses. Light, dark and tinted variants still follow macOS automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)

                        HStack(spacing: 12) {
                            appIconPreviewCard(
                                previewImage: AppIconModeManager.previewImage(for: .classic),
                                title: "QuartzNotch",
                                isSelected: appIconChoice == .classic,
                                action: {
                                    appIconChoice = .classic
                                    AppIconModeManager.applyCurrentAppIconOverride()
                                }
                            )

                            appIconPreviewCard(
                                previewImage: AppIconModeManager.previewImage(for: .quartzNew),
                                title: "Minimal",
                                isSelected: appIconChoice == .quartzNew,
                                action: {
                                    appIconChoice = .quartzNew
                                    AppIconModeManager.applyCurrentAppIconOverride()
                                }
                            )
                        }
                        .id(appIconPreviewMonitor.signature)
                    }
                }
                .padding(.top, 6)
            }

            Section {
                Toggle(isOn: $cinemaMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cinema mode")
                        Text("Enlarges the notch 2× for screen recordings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .liveAccentToggleTint()
            } header: {
                Text("Presentation")
            }

            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
                .liveAccentToggleTint()
                Defaults.Toggle(key: .hideMusicSourceAppIcon) {
                    Text("Hide music source icon")
                }
                .liveAccentToggleTint()
                Toggle("Disable Liquid Glass", isOn: $forceLiquidGlassCompatibilityFallback)
                    .liveAccentToggleTint()
            } header: {
                Text("Window Rendering")
            }
            
            Section {
                LabeledContent("Hide on screen capture") {
                    AccentMenuPicker(
                        selection: $hideFromScreenRecordingMode,
                        options: ScreenRecordingVisibilityMode.allCases,
                        title: { screenRecordingModeLabel($0) },
                        menuWidth: 220
                    )
                }
            } header: {
                Text("Privacy & Capture")
            }

            Section {
                LabeledContent("App language") {
                    AccentMenuPicker(
                        selection: $appLanguage,
                        options: AppLanguage.allCases,
                        title: { $0.displayName },
                        menuWidth: 220
                    )
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Restart QuartzNotch to apply language changes.")
            }
            .onChange(of: appLanguage) { _, newLanguage in
                AppLanguageManager.apply(newLanguage)
            }
        }
        .accentFormRefresh()
        .navigationTitle("Advanced")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        NSColor.applyEffectiveAccentOverride()
        NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        AccentTintPulse.shared.ping()
    }

    private func screenRecordingModeLabel(_ mode: ScreenRecordingVisibilityMode) -> String {
        switch mode {
        case .disabled:
            return "Disabled"
        case .fullyHidden:
            return "Hide during capture"
        case .onlyWhenNotInUse:
            return "When closed and inactive"
        case .onlyWhenClosed:
            return "When closed"
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func saveCustomColorSilently(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }

    @ViewBuilder
    private func appIconPreviewCard(previewImage: NSImage?, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                    } else {
                        Color.clear
                    }
                }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.effectiveAccent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                    }

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? Color.effectiveAccent : .secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

private struct SettingsSliderHapticModifier: ViewModifier {
    let value: Double
    let lowerBound: Double
    let step: Double

    @State private var lastTick: Int?

    private func tick(for value: Double) -> Int {
        Int(((value - lowerBound) / step).rounded())
    }

    private func performHapticIfNeeded(for newValue: Double) {
        let newTick = tick(for: newValue)
        guard let lastTick else {
            self.lastTick = newTick
            return
        }
        guard newTick != lastTick else { return }
        self.lastTick = newTick
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                lastTick = tick(for: value)
            }
            .onChange(of: value) { _, newValue in
                performHapticIfNeeded(for: newValue)
            }
    }
}

private extension View {
    func settingsSliderHaptics(value: Double, lowerBound: Double, step: Double) -> some View {
        modifier(SettingsSliderHapticModifier(value: value, lowerBound: lowerBound, step: step))
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .accentFormRefresh()
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 3)
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 3)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 3)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}

private enum AccentMenuStyle {
    static let closedChevronBackgroundColor = Color(nsColor: .tertiaryLabelColor).opacity(0.28)
    static let closedHoverBackgroundColor = closedChevronBackgroundColor
    static var openMenuHighlightNSColor: NSColor {
        let base = NSColor.effectiveAccent
        let saturated = base.usingColorSpace(.deviceRGB).map {
            NSColor(
                deviceRed: min(1.0, $0.redComponent * 1.05),
                green: max(0.0, $0.greenComponent * 0.98),
                blue: min(1.0, $0.blueComponent * 1.07),
                alpha: $0.alphaComponent
            )
        } ?? base
        let darkened = saturated.shadow(withLevel: 0.28) ?? saturated.blended(withFraction: 0.28, of: .black) ?? saturated
        return darkened.withAlphaComponent(0.97)
    }
    static let cornerRadius: CGFloat = 7
    static let itemHeight: CGFloat = 27.75
}

private struct AccentMenuItemStyle: Equatable {
    let itemHeight: CGFloat
    let contentInsets: NSEdgeInsets
    let highlightInsets: NSEdgeInsets
    let preferredWidthExtra: CGFloat

    static func == (lhs: AccentMenuItemStyle, rhs: AccentMenuItemStyle) -> Bool {
        lhs.itemHeight == rhs.itemHeight
        && NSEdgeInsetsEqual(lhs.contentInsets, rhs.contentInsets)
        && NSEdgeInsetsEqual(lhs.highlightInsets, rhs.highlightInsets)
        && lhs.preferredWidthExtra == rhs.preferredWidthExtra
    }

    static let picker = AccentMenuItemStyle(
        itemHeight: AccentMenuStyle.itemHeight,
        contentInsets: NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8),
        highlightInsets: NSEdgeInsets(top: 1, left: 5, bottom: 1, right: 5),
        preferredWidthExtra: 26
    )

    static let contextMenu = AccentMenuItemStyle(
        itemHeight: 23,
        contentInsets: NSEdgeInsets(top: 1, left: 15, bottom: 1, right: 15),
        highlightInsets: NSEdgeInsets(top: 0.0, left: 4.0, bottom: 0.0, right: 4.0),
        preferredWidthExtra: 32
    )
}

private final class AccentMenuAnchorView: NSView {}

private struct AccentMenuClickCapture: NSViewRepresentable {
    let onMouseDown: (NSView) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onMouseDown = onMouseDown
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onHoverChanged = onHoverChanged
    }

    final class CaptureView: NSView {
        var onMouseDown: ((NSView) -> Void)?
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingAreaRef: NSTrackingArea?

        private func updateHoverFromCurrentPointer() {
            guard let window else {
                onHoverChanged?(false)
                return
            }
            let windowPoint = window.mouseLocationOutsideOfEventStream
            let localPoint = convert(windowPoint, from: nil)
            onHoverChanged?(bounds.contains(localPoint))
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            trackingAreaRef = trackingArea
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            updateHoverFromCurrentPointer()
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHoverChanged?(bounds.contains(point))
        }

        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
            DispatchQueue.main.async { [weak self] in
                self?.updateHoverFromCurrentPointer()
            }
        }

        override func mouseDown(with event: NSEvent) {
            onMouseDown?(self)
        }
    }
}

private struct AccentMenuAnchorReader: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AccentMenuAnchorView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

private struct AccentMenuEntry: Identifiable {
    let id: AnyHashable
    let titleText: String
    let style: AccentMenuItemStyle
    let content: (AccentMenuItemHoverState) -> AnyView
    let activateOnMouseUp: Bool
    let action: () -> Void
}

@MainActor
private final class AccentMenuItemHoverState: ObservableObject {
    var isHovered = false
}

private final class AccentMenuActionTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}

private final class AccentMenuItemView: NSView {
    private let hoverState = AccentMenuItemHoverState()
    private let contentHostingView: NSHostingView<AnyView>
    private let contentBuilder: (AccentMenuItemHoverState) -> AnyView
    private let activateOnMouseUp: Bool
    private let action: () -> Void
    private let style: AccentMenuItemStyle
    private var trackingAreaRef: NSTrackingArea?
    private let highlightLayer = CALayer()

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            highlightLayer.backgroundColor = isHovered ? AccentMenuStyle.openMenuHighlightNSColor.cgColor : NSColor.clear.cgColor
            CATransaction.commit()
            hoverState.isHovered = isHovered
            contentHostingView.rootView = contentBuilder(hoverState)
        }
    }

    init(
        style: AccentMenuItemStyle,
        content: @escaping (AccentMenuItemHoverState) -> AnyView,
        activateOnMouseUp: Bool = false,
        width: CGFloat = 0,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.contentBuilder = content
        self.contentHostingView = NSHostingView(rootView: content(hoverState))
        self.activateOnMouseUp = activateOnMouseUp
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: style.itemHeight))

        wantsLayer = true
        layer?.cornerRadius = AccentMenuStyle.cornerRadius
        layer?.backgroundColor = NSColor.clear.cgColor
        highlightLayer.cornerRadius = AccentMenuStyle.cornerRadius
        highlightLayer.backgroundColor = NSColor.clear.cgColor
        highlightLayer.actions = [
            "backgroundColor": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "opacity": NSNull()
        ]
        layer?.addSublayer(highlightLayer)

        contentHostingView.translatesAutoresizingMaskIntoConstraints = false
        contentHostingView.wantsLayer = true
        contentHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentHostingView)

        NSLayoutConstraint.activate([
            contentHostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.contentInsets.left),
            contentHostingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.contentInsets.right),
            contentHostingView.topAnchor.constraint(equalTo: topAnchor, constant: style.contentInsets.top),
            contentHostingView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -style.contentInsets.bottom)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = CGRect(
            x: style.highlightInsets.left,
            y: style.highlightInsets.top,
            width: max(0, bounds.width - style.highlightInsets.left - style.highlightInsets.right),
            height: max(0, bounds.height - style.highlightInsets.top - style.highlightInsets.bottom)
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isHovered = bounds.contains(point)
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
    }

    func preferredWidth() -> CGFloat {
        layoutSubtreeIfNeeded()
        let fitting = contentHostingView.fittingSize.width
        return ceil(fitting + style.preferredWidthExtra)
    }

    func setMenuWidth(_ width: CGFloat) {
        var newFrame = frame
        newFrame.size.width = width
        frame = newFrame
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard !activateOnMouseUp else { return }
        action()
        enclosingMenuItem?.menu?.cancelTracking()
    }

    override func mouseUp(with event: NSEvent) {
        guard activateOnMouseUp else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        action()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

private final class AccentMenuDelegate: NSObject, NSMenuDelegate {
    private var itemViews: [ObjectIdentifier: AccentMenuItemView] = [:]
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        super.init()
    }

    func register(_ view: AccentMenuItemView, for item: NSMenuItem) {
        itemViews[ObjectIdentifier(item)] = view
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        let highlightedID = item.map(ObjectIdentifier.init)
        for (identifier, view) in itemViews {
            view.setHovered(identifier == highlightedID)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        for view in itemViews.values {
            view.setHovered(false)
        }
        onClose?()
    }
}

private enum AccentMenuPresenter {
    @MainActor
    static func present(entries: [AccentMenuEntry], from anchorView: NSView, preferredWidth: CGFloat? = nil, selectedIndex: Int? = nil, onClose: (() -> Void)? = nil) {
        let width = preferredWidth ?? 0
        let menu = makeMenu(entries: entries, width: width, onClose: onClose)
        let positioningItem = selectedIndex.flatMap { menu.items.indices.contains($0) ? menu.items[$0] : nil }
        menu.popUp(positioning: positioningItem, at: NSPoint(x: 0, y: anchorView.bounds.height + 4), in: anchorView)
    }

    @MainActor
    static func present(entries: [AccentMenuEntry], at point: NSPoint, in anchorView: NSView, preferredWidth: CGFloat? = nil, onClose: (() -> Void)? = nil) {
        let width = preferredWidth ?? 0
        let menu = makeMenu(entries: entries, width: width, onClose: onClose)
        menu.popUp(positioning: nil, at: point, in: anchorView)
    }

    private static func makeMenu(entries: [AccentMenuEntry], width: CGFloat, onClose: (() -> Void)? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let targets = NSMutableArray()
        let delegate = AccentMenuDelegate(onClose: onClose)
        menu.delegate = delegate
        targets.add(delegate)
        var pendingViews: [AccentMenuItemView] = []
        var widestViewWidth: CGFloat = max(width, 0)

        for entry in entries {
            let item = NSMenuItem()
            item.title = entry.titleText
            item.isEnabled = true
            let target = AccentMenuActionTarget(action: entry.action)
            targets.add(target)
            item.representedObject = targets
            item.target = target
            item.action = #selector(AccentMenuActionTarget.performAction(_:))
            let view = AccentMenuItemView(
                style: entry.style,
                content: entry.content
                ,
                activateOnMouseUp: entry.activateOnMouseUp
            ) {
                target.performAction(nil)
            }
            widestViewWidth = max(widestViewWidth, view.preferredWidth())
            pendingViews.append(view)
            delegate.register(view, for: item)
            item.view = view
            menu.addItem(item)
        }

        for view in pendingViews {
            view.setMenuWidth(widestViewWidth)
        }
        menu.minimumWidth = widestViewWidth

        return menu
    }
}

struct AccentMenuPicker<Value: Hashable>: View {
    enum Prominence {
        case regular
        case emphasized
    }

    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var menuWidth: CGFloat? = nil
    var controlSize: ControlSize = .regular
    var prominence: Prominence = .regular
    var leadingView: ((Value, Bool) -> AnyView?)? = nil
    var onSelect: ((Value) -> Void)? = nil

    @State private var anchorView: NSView?
    @State private var isHovered = false
    @State private var isMenuPresented = false

    private var isControlHovered: Bool {
        isHovered && !isMenuPresented
    }

    private func localizedTitle(for value: Value) -> String {
        NSLocalizedString(title(value), comment: "")
    }

    @MainActor
    private func presentMenu(from anchorView: NSView) {
        isHovered = false
        isMenuPresented = true

        let entries = options.map { value in
            AccentMenuEntry(
                id: AnyHashable(value),
                titleText: localizedTitle(for: value),
                style: .picker,
                content: { hoverState in
                    AnyView(menuRow(for: value, isSelected: value == selection, hoverState: hoverState))
                },
                activateOnMouseUp: false,
                action: {
                    selection = value
                    onSelect?(value)
                }
            )
        }
        let selectedIndex = options.firstIndex(where: { $0 == selection })
        AccentMenuPresenter.present(
            entries: entries,
            from: anchorView,
            preferredWidth: nil,
            selectedIndex: selectedIndex,
            onClose: {
                isMenuPresented = false
            }
        )
    }

    private var leadingPadding: CGFloat {
        if prominence == .emphasized {
            return switch controlSize {
            case .mini: 13
            case .small: 14
            case .regular: 14
            case .large: 14
            case .extraLarge: 14
            @unknown default: 14
            }
        }
        return switch controlSize {
        case .mini: 12
        case .small: 13
        case .regular: 13
        case .large: 13
        case .extraLarge: 13
        @unknown default: 13
        }
    }

    private var trailingPadding: CGFloat {
        if prominence == .emphasized {
            return switch controlSize {
            case .mini: 4
            case .small: 5
            case .regular: 5
            case .large: 5
            case .extraLarge: 5
            @unknown default: 5
            }
        }
        return switch controlSize {
        case .mini: 3
        case .small: 4
        case .regular: 4
        case .large: 4
        case .extraLarge: 4
        @unknown default: 4
        }
    }

    private var contentHeight: CGFloat {
        if prominence == .emphasized {
            return switch controlSize {
            case .mini: 22
            case .small: 23
            case .regular: 23
            case .large: 23
            case .extraLarge: 23
            @unknown default: 23
            }
        }
        return switch controlSize {
        case .mini: 21
        case .small: 22
        case .regular: 22
        case .large: 22
        case .extraLarge: 22
        @unknown default: 22
        }
    }

    private var font: Font {
        if prominence == .emphasized {
            return switch controlSize {
            case .mini: Font.system(size: 11.5, weight: .medium)
            case .small: Font.system(size: 12.5, weight: .medium)
            case .regular: Font.system(size: 13.5, weight: .medium)
            case .large: Font.system(size: 13.5, weight: .medium)
            case .extraLarge: Font.system(size: 13.5, weight: .medium)
            @unknown default: Font.system(size: 13.5, weight: .medium)
            }
        }
        return switch controlSize {
        case .mini: Font.system(size: 11)
        case .small: Font.system(size: 12)
        case .regular: Font.body
        case .large: Font.body
        case .extraLarge: Font.body
        @unknown default: Font.body
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(localizedTitle(for: selection))
                .lineLimit(1)
                .foregroundStyle(.primary)
            ZStack {
                Circle()
                    .fill(isControlHovered ? .clear : AccentMenuStyle.closedChevronBackgroundColor)
                    .frame(width: prominence == .emphasized ? 22 : 21, height: prominence == .emphasized ? 22 : 21)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: prominence == .emphasized ? 10.4 : 10.1, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.96))
            }
        }
        .font(font)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .frame(height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(isControlHovered ? AccentMenuStyle.closedHoverBackgroundColor : .clear)
                .scaleEffect(y: isControlHovered ? 1.06 : 1.0, anchor: .center)
        )
        .contentShape(Rectangle())
        .background(AccentMenuAnchorReader { anchorView = $0 })
        .overlay {
            AccentMenuClickCapture(
                onMouseDown: { clickedView in
                    let anchor = anchorView ?? clickedView
                    presentMenu(from: anchor)
                },
                onHoverChanged: { isHovered = $0 }
            )
        }
    }

    @ViewBuilder
    private func menuRow(for value: Value, isSelected: Bool, hoverState: AccentMenuItemHoverState) -> some View {
        HStack(spacing: 8) {
            Group {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hoverState.isHovered ? .white : .primary)
                } else {
                    Color.clear
                        .frame(width: 11, height: 11)
                }
            }
            .frame(width: 12, alignment: .leading)

            if let leading = leadingView?(value, hoverState.isHovered) {
                leading
            }

            Text(localizedTitle(for: value))
                .lineLimit(1)
                .foregroundStyle(hoverState.isHovered ? .white : .primary)

            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccentContextMenuCapture: NSViewRepresentable {
    let onRightClick: (NSView, NSPoint) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CaptureView: NSView {
        var onRightClick: ((NSView, NSPoint) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }

            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return bounds.contains(point) ? self : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onRightClick?(self, point)
        }
    }
}

struct AccentContextMenuAction: Identifiable {
    let id = UUID()
    let title: String
    let keyboardShortcut: String?
    let action: () -> Void
}

struct AccentContextMenuModifier: ViewModifier {
    let actions: [AccentContextMenuAction]
    var menuWidth: CGFloat? = nil

    func body(content: Content) -> some View {
        content.overlay {
            AccentContextMenuCapture { anchorView, point in
                let entries = actions.map { action in
                    AccentMenuEntry(
                        id: action.id,
                        titleText: action.title,
                        style: .contextMenu,
                        content: { hoverState in
                            AnyView(
                                HStack(spacing: 8) {
                                    Text(action.title)
                                        .font(.system(size: 13.0, weight: .regular))
                                        .foregroundStyle(hoverState.isHovered ? .white : .primary)
                                    Spacer(minLength: 8)
                                    if let keyboardShortcut = action.keyboardShortcut {
                                        Text(keyboardShortcut)
                                            .font(.system(size: 13.0, weight: .regular))
                                            .foregroundStyle(hoverState.isHovered ? .white.opacity(0.9) : .secondary)
                                    }
                                }
                                .frame(alignment: .leading)
                            )
                        },
                        activateOnMouseUp: true,
                        action: action.action
                    )
                }
                AccentMenuPresenter.present(entries: entries, at: point, in: anchorView, preferredWidth: menuWidth)
            }
            .allowsHitTesting(true)
        }
    }
}

extension View {
    func accentContextMenu(actions: [AccentContextMenuAction], menuWidth: CGFloat? = nil) -> some View {
        modifier(AccentContextMenuModifier(actions: actions, menuWidth: menuWidth))
    }
}
