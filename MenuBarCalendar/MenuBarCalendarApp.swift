import SwiftUI
import EventKit
import AppKit

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
    var popover: NSPopover!
    let calendarService = CalendarService()
    let settings = SettingsManager.shared
    var hostingView: NSHostingView<MenuBarLabelView>?
    var isPopoverShown = false
    
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContent(calendarService: calendarService, settings: settings)
        )
        popover.delegate = self
        
        // Setup custom view for status item
        updateStatusItemView()
        
        // Observe settings changes
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemView()
                }
            }
            .store(in: &cancellables)
        
        // Observe calendar service changes
        calendarService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemView()
                }
            }
            .store(in: &cancellables)
    }
    
    func updateStatusItemView() {
        guard let button = statusItem.button else { return }
        
        // Remove existing subviews
        button.subviews.forEach { $0.removeFromSuperview() }
        
        // Create SwiftUI view with click state
        let labelView = MenuBarLabelView(
            calendarService: calendarService,
            settings: settings,
            isActive: isPopoverShown
        )
        
        let hostingView = NSHostingView(rootView: labelView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        button.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        
        // Update button size
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        statusItem.length = size.width + 4
        
        button.action = #selector(togglePopover)
        button.target = self
    }
    
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            isPopoverShown = true
            updateStatusItemView()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        isPopoverShown = false
        updateStatusItemView()
    }
}

// MARK: - Menu Bar Label SwiftUI View

struct MenuBarLabelView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var settings: SettingsManager
    var isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            // Indicator
            if settings.indicatorStyle != .none {
                indicatorView
            }
            
            Text(calendarService.menuBarTitle)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, settings.showBackground ? 10 : 4)
        .padding(.vertical, settings.showBackground ? 4 : 2)
        .background(
            Group {
                if settings.showBackground {
                    Capsule()
                        .fill(backgroundColor)
                }
            }
        )
    }
    
    @ViewBuilder
    private var indicatorView: some View {
        let color = indicatorColor
        
        switch settings.indicatorStyle {
        case .bar:
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 12)
        case .dot:
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        case .none:
            EmptyView()
        }
    }
    
    private var indicatorColor: Color {
        switch settings.indicatorColorMode {
        case .calendar:
            return calendarColor
        case .custom:
            return settings.customIndicatorColor
        case .accent:
            return .accentColor
        }
    }
    
    private var calendarColor: Color {
        if let event = calendarService.currentEvent ?? calendarService.nextEvent,
           let cgColor = event.calendarColor {
            return Color(cgColor: cgColor)
        }
        return .blue
    }
    
    private var backgroundColor: Color {
        let baseColor: Color
        
        switch settings.backgroundColorMode {
        case .calendar:
            // Use calendar color with adjustments
            baseColor = calendarColor.adjustedForBackground(
                saturationDelta: settings.backgroundSaturationAdjust,
                brightnessDelta: settings.backgroundBrightnessAdjust,
                opacity: settings.backgroundOpacity
            )
        case .custom:
            baseColor = settings.customBackgroundColor
        case .gray:
            baseColor = Color.gray.opacity(0.3)
        }
        
        // Brighten when active (clicked)
        if isActive {
            return baseColor.opacity(min(1.0, (baseColor.opacity ?? 0.3) + 0.15))
        }
        
        return baseColor
    }
}

// Extension to get opacity from Color (approximate)
extension Color {
    var opacity: Double? {
        return nil // Will use default
    }
}

import Combine
