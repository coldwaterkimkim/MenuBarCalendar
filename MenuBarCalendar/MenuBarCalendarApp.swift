import SwiftUI
import AppKit
import Combine

@main
struct MenuBarCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(calendarService: appDelegate.calendarService, settings: appDelegate.settings)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let calendarService = CalendarService()
    let settings = SettingsManager.shared
    var hostingView: NSHostingView<MenuBarLabelView>?
    var isContextMenuShown = false

    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var lastStatusItemLength: CGFloat = 0
    private var isRequestingCalendarAccess = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Setup custom view for status item
        updateStatusItemView()

        let calendarUpdates = Publishers.Merge3(
            calendarService.$menuBarTitle.map { _ in () },
            calendarService.$currentEvent.map { _ in () },
            calendarService.$nextEvent.map { _ in () }
        )

        // Coalesce bursts from menu-bar-relevant changes into one status item redraw.
        Publishers.Merge(
            settings.menuBarAppearanceChanged,
            calendarUpdates
        )
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemView()
            }
            .store(in: &cancellables)
    }

    func updateStatusItemView() {
        guard let button = statusItem.button else { return }

        let labelView = makeMenuBarLabelView()

        let hostingView: NSHostingView<MenuBarLabelView>
        if let existingHostingView = self.hostingView {
            existingHostingView.rootView = labelView
            hostingView = existingHostingView
        } else {
            let newHostingView = NSHostingView(rootView: labelView)
            newHostingView.translatesAutoresizingMaskIntoConstraints = false

            button.addSubview(newHostingView)

            NSLayoutConstraint.activate([
                newHostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                newHostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                newHostingView.topAnchor.constraint(equalTo: button.topAnchor),
                newHostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])

            self.hostingView = newHostingView
            hostingView = newHostingView
        }

        // Update button size
        hostingView.layoutSubtreeIfNeeded()
        let newLength = ceil(hostingView.fittingSize.width + 4)
        if abs(newLength - lastStatusItemLength) > 0.5 {
            statusItem.length = newLength
            lastStatusItemLength = newLength
        }

        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
    }

    private func makeMenuBarLabelView() -> MenuBarLabelView {
        let calendarColor = menuBarCalendarColor
        let backgroundColor: Color

        switch settings.backgroundColorMode {
        case .calendar:
            backgroundColor = calendarColor.adjustedForBackground(
                saturationDelta: settings.backgroundSaturationAdjust,
                brightnessDelta: settings.backgroundBrightnessAdjust,
                opacity: settings.backgroundOpacity
            )
        case .custom:
            backgroundColor = settings.customBackgroundColor
        case .gray:
            backgroundColor = Color.gray.opacity(0.3)
        }

        return MenuBarLabelView(
            title: calendarService.menuBarTitle,
            indicatorStyle: settings.indicatorStyle,
            indicatorColor: menuBarIndicatorColor(calendarColor: calendarColor),
            showBackground: settings.showBackground,
            backgroundColor: backgroundColor,
            isActive: isContextMenuShown
        )
    }

    private var menuBarCalendarColor: Color {
        if let event = calendarService.currentEvent ?? calendarService.nextEvent,
           let cgColor = event.calendarColor {
            return Color(cgColor: cgColor)
        }
        return .blue
    }

    private func menuBarIndicatorColor(calendarColor: Color) -> Color {
        switch settings.indicatorColorMode {
        case .calendar:
            return calendarColor
        case .custom:
            return settings.customIndicatorColor
        case .accent:
            return .accentColor
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(from: sender)
        } else {
            openCalendarOrRequestAccess()
        }
    }

    private func openCalendarOrRequestAccess() {
        let wasAuthorized = calendarService.authorizationStatus == .authorized
        calendarService.checkAuthorizationStatus(refreshIfAuthorized: false)

        switch calendarService.authorizationStatus {
        case .authorized:
            if !wasAuthorized {
                calendarService.refreshEvents(forceFetch: true, refreshSources: true)
            }
            calendarService.openCalendarApp()
        case .notDetermined:
            requestCalendarAccess()
        case .denied:
            showCalendarPermissionAlert()
        }
    }

    private func requestCalendarAccess() {
        guard !isRequestingCalendarAccess else { return }
        isRequestingCalendarAccess = true

        Task { @MainActor in
            await calendarService.requestAccess()
            isRequestingCalendarAccess = false

            if calendarService.authorizationStatus == .authorized {
                calendarService.openCalendarApp()
            } else {
                showCalendarPermissionAlert()
            }
        }
    }

    private func showCalendarPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "캘린더 접근 권한이 필요해"
        alert.informativeText = "이 앱이 메뉴바에 다음 일정을 표시하려면 macOS 캘린더 접근 권한이 필요해."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openCalendarPrivacySettings()
        }
    }

    private func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        isContextMenuShown = true
        updateStatusItemView()

        let menu = makeContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)

        isContextMenuShown = false
        updateStatusItemView()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(refreshCalendar), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "설정...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    @objc private func refreshCalendar() {
        calendarService.checkAuthorizationStatus(refreshIfAuthorized: false)

        switch calendarService.authorizationStatus {
        case .authorized:
            calendarService.refreshEvents(forceFetch: true, refreshSources: true)
        case .notDetermined:
            requestCalendarAccess()
        case .denied:
            showCalendarPermissionAlert()
        }
    }

    @objc private func openSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: SettingsView(calendarService: calendarService, settings: settings)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "설정"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }
}

// MARK: - Menu Bar Label SwiftUI View

struct MenuBarLabelView: View {
    let title: String
    let indicatorStyle: IndicatorStyle
    let indicatorColor: Color
    let showBackground: Bool
    let backgroundColor: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            // Indicator
            if indicatorStyle != .none {
                indicatorView
            }

            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, showBackground ? 10 : 4)
        .padding(.vertical, showBackground ? 4 : 2)
        .background(
            Group {
                if showBackground {
                    Capsule()
                        .fill(effectiveBackgroundColor)
                }
            }
        )
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicatorStyle {
        case .bar:
            RoundedRectangle(cornerRadius: 1)
                .fill(indicatorColor)
                .frame(width: 3, height: 12)
        case .dot:
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
        case .none:
            EmptyView()
        }
    }

    private var effectiveBackgroundColor: Color {
        if isActive {
            return backgroundColor.opacity(0.45)
        }

        return backgroundColor
    }
}
