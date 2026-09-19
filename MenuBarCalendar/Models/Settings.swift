import Foundation
import Combine
import SwiftUI

enum OverlapRule: String, CaseIterable, Codable {
    case earliestEnd = "earliestEnd"
    case earliestStart = "earliestStart"

    var displayName: String {
        switch self {
        case .earliestEnd: return "가장 빨리 끝나는 일정"
        case .earliestStart: return "가장 먼저 시작한 일정"
        }
    }
}

enum IndicatorStyle: String, CaseIterable, Codable {
    case none = "none"
    case bar = "bar"
    case dot = "dot"

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .bar: return "바 (Notion 스타일)"
        case .dot: return "점"
        }
    }
}

enum IndicatorColorMode: String, CaseIterable, Codable {
    case calendar = "calendar"
    case custom = "custom"
    case accent = "accent"

    var displayName: String {
        switch self {
        case .calendar: return "캘린더 색상"
        case .custom: return "사용자 지정"
        case .accent: return "시스템 강조 색상"
        }
    }
}

enum BackgroundColorMode: String, CaseIterable, Codable {
    case calendar = "calendar"
    case custom = "custom"
    case gray = "gray"

    var displayName: String {
        switch self {
        case .calendar: return "캘린더 색상 기반"
        case .custom: return "사용자 지정"
        case .gray: return "회색 (기본)"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    let eventDisplayChanged = PassthroughSubject<Void, Never>()
    let menuBarAppearanceChanged = PassthroughSubject<Void, Never>()

    // Trigger for view updates
    @Published private var updateTrigger = UUID()

    private func triggerUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTrigger = UUID()
        }
    }

    // MARK: - Calendar Settings

    var excludedCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedCalendarIDs") ?? []) }
        set {
            defaults.set(Array(newValue), forKey: "excludedCalendarIDs")
            eventDisplayChanged.send()
            triggerUpdate()
        }
    }

    var overlapRule: OverlapRule {
        get { OverlapRule(rawValue: defaults.string(forKey: "overlapRule") ?? "") ?? .earliestEnd }
        set {
            defaults.set(newValue.rawValue, forKey: "overlapRule")
            eventDisplayChanged.send()
            triggerUpdate()
        }
    }

    var titleMaxLength: Int {
        get { defaults.object(forKey: "titleMaxLength") as? Int ?? 24 }
        set {
            defaults.set(newValue, forKey: "titleMaxLength")
            eventDisplayChanged.send()
            triggerUpdate()
        }
    }

    var lookaheadHours: Int {
        get { defaults.object(forKey: "lookaheadHours") as? Int ?? 24 }
        set {
            defaults.set(newValue, forKey: "lookaheadHours")
            eventDisplayChanged.send()
            triggerUpdate()
        }
    }

    // MARK: - Appearance Settings

    var indicatorStyle: IndicatorStyle {
        get { IndicatorStyle(rawValue: defaults.string(forKey: "indicatorStyle") ?? "") ?? .bar }
        set {
            defaults.set(newValue.rawValue, forKey: "indicatorStyle")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var indicatorColorMode: IndicatorColorMode {
        get { IndicatorColorMode(rawValue: defaults.string(forKey: "indicatorColorMode") ?? "") ?? .calendar }
        set {
            defaults.set(newValue.rawValue, forKey: "indicatorColorMode")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var customIndicatorColor: Color {
        get {
            if let colorData = defaults.data(forKey: "customIndicatorColor"),
               let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
                return Color(nsColor)
            }
            return .blue
        }
        set {
            if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(newValue), requiringSecureCoding: false) {
                defaults.set(colorData, forKey: "customIndicatorColor")
            }
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    // MARK: - Background Settings

    var showBackground: Bool {
        get { defaults.object(forKey: "showBackground") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "showBackground")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var backgroundColorMode: BackgroundColorMode {
        get { BackgroundColorMode(rawValue: defaults.string(forKey: "backgroundColorMode") ?? "") ?? .gray }
        set {
            defaults.set(newValue.rawValue, forKey: "backgroundColorMode")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var customBackgroundColor: Color {
        get {
            if let colorData = defaults.data(forKey: "customBackgroundColor"),
               let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
                return Color(nsColor)
            }
            return Color.gray.opacity(0.3)
        }
        set {
            if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: NSColor(newValue), requiringSecureCoding: false) {
                defaults.set(colorData, forKey: "customBackgroundColor")
            }
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    // HSL adjustments for calendar-based background
    var backgroundSaturationAdjust: Double {
        get { defaults.object(forKey: "backgroundSaturationAdjust") as? Double ?? -0.5 }
        set {
            defaults.set(newValue, forKey: "backgroundSaturationAdjust")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var backgroundBrightnessAdjust: Double {
        get { defaults.object(forKey: "backgroundBrightnessAdjust") as? Double ?? -0.3 }
        set {
            defaults.set(newValue, forKey: "backgroundBrightnessAdjust")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    var backgroundOpacity: Double {
        get { defaults.object(forKey: "backgroundOpacity") as? Double ?? 0.4 }
        set {
            defaults.set(newValue, forKey: "backgroundOpacity")
            menuBarAppearanceChanged.send()
            triggerUpdate()
        }
    }

    private init() {}
}

// MARK: - Color Extension for HSL Adjustments

extension Color {
    func adjustedForBackground(saturationDelta: Double, brightnessDelta: Double, opacity: Double) -> Color {
        let nsColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // Convert to HSB
        if let converted = nsColor.usingColorSpace(.deviceRGB) {
            converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        }

        // Apply adjustments
        let newSaturation = max(0, min(1, saturation + CGFloat(saturationDelta)))
        let newBrightness = max(0, min(1, brightness + CGFloat(brightnessDelta)))

        return Color(hue: Double(hue), saturation: Double(newSaturation), brightness: Double(newBrightness), opacity: opacity)
    }
}
