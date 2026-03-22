import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("일반", systemImage: "gear")
                }
            
            AppearanceSettingsView(settings: settings, calendarService: calendarService)
                .tabItem {
                    Label("모양", systemImage: "paintbrush")
                }
            
            CalendarFilterView(calendarService: calendarService, settings: settings)
                .tabItem {
                    Label("캘린더", systemImage: "calendar")
                }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        Form {
            Section("표시 설정") {
                Picker("제목 최대 길이", selection: $settings.titleMaxLength) {
                    Text("16자").tag(16)
                    Text("24자").tag(24)
                    Text("32자").tag(32)
                }
                
                Picker("조회 범위", selection: $settings.lookaheadHours) {
                    Text("6시간").tag(6)
                    Text("24시간").tag(24)
                    Text("48시간").tag(48)
                }
                
                Stepper("다가오는 일정 표시 개수: \(settings.upcomingEventsCount)", 
                       value: $settings.upcomingEventsCount, 
                       in: 3...10)
            }
            
            Section("겹치는 일정 처리") {
                Picker("우선순위", selection: $settings.overlapRule) {
                    ForEach(OverlapRule.allCases, id: \.self) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }
            }
            
            Section("하루종일 이벤트") {
                Toggle("하루종일 이벤트 표시", isOn: $settings.showAllDayEvents)
                
                if settings.showAllDayEvents {
                    Text("하루종일 이벤트는 목록에만 표시되며, 메뉴바 타이틀에는 우선 표시되지 않습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var calendarService: CalendarService
    
    var body: some View {
        Form {
            Section("인디케이터 스타일") {
                Picker("스타일", selection: $settings.indicatorStyle) {
                    ForEach(IndicatorStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("인디케이터 색상") {
                Picker("색상 모드", selection: $settings.indicatorColorMode) {
                    ForEach(IndicatorColorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                
                if settings.indicatorColorMode == .custom {
                    ColorPicker("사용자 지정 색상", selection: $settings.customIndicatorColor)
                }
            }
            
            Section("배경") {
                Toggle("배경 표시", isOn: $settings.showBackground)
                
                if settings.showBackground {
                    Picker("배경 색상 모드", selection: $settings.backgroundColorMode) {
                        ForEach(BackgroundColorMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    
                    if settings.backgroundColorMode == .custom {
                        ColorPicker("사용자 지정 색상", selection: $settings.customBackgroundColor)
                    }
                    
                    if settings.backgroundColorMode == .calendar {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("캘린더 색상 조정")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("채도")
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: $settings.backgroundSaturationAdjust, in: -1.0...0.0, step: 0.1)
                                Text(String(format: "%.0f%%", (settings.backgroundSaturationAdjust + 1) * 100))
                                    .frame(width: 40)
                            }
                            
                            HStack {
                                Text("밝기")
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: $settings.backgroundBrightnessAdjust, in: -0.5...0.2, step: 0.1)
                                Text(String(format: "%+.0f%%", settings.backgroundBrightnessAdjust * 100))
                                    .frame(width: 40)
                            }
                            
                            HStack {
                                Text("투명도")
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: $settings.backgroundOpacity, in: 0.1...1.0, step: 0.1)
                                Text(String(format: "%.0f%%", settings.backgroundOpacity * 100))
                                    .frame(width: 40)
                            }
                        }
                    }
                }
            }
            
            Section("미리보기") {
                HStack {
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if settings.indicatorStyle != .none {
                            previewIndicator
                        }
                        Text("회의 · 30분 후")
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, settings.showBackground ? 10 : 0)
                    .padding(.vertical, settings.showBackground ? 4 : 0)
                    .background(
                        Group {
                            if settings.showBackground {
                                Capsule()
                                    .fill(previewBackgroundColor)
                            }
                        }
                    )
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var previewIndicator: some View {
        let color = previewColor
        
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
    
    private var previewColor: Color {
        switch settings.indicatorColorMode {
        case .calendar:
            return calendarSampleColor
        case .custom:
            return settings.customIndicatorColor
        case .accent:
            return .accentColor
        }
    }
    
    private var calendarSampleColor: Color {
        if let event = calendarService.currentEvent ?? calendarService.nextEvent,
           let cgColor = event.calendarColor {
            return Color(cgColor: cgColor)
        }
        return .blue
    }
    
    private var previewBackgroundColor: Color {
        switch settings.backgroundColorMode {
        case .calendar:
            return calendarSampleColor.adjustedForBackground(
                saturationDelta: settings.backgroundSaturationAdjust,
                brightnessDelta: settings.backgroundBrightnessAdjust,
                opacity: settings.backgroundOpacity
            )
        case .custom:
            return settings.customBackgroundColor
        case .gray:
            return Color.gray.opacity(0.3)
        }
    }
}

// MARK: - Calendar Filter

struct CalendarFilterView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("표시할 캘린더를 선택하세요")
                .font(.headline)
            
            Text("선택 해제된 캘린더의 일정은 메뉴바와 목록에서 숨겨집니다.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if calendarService.authorizationStatus != .authorized {
                Text("캘린더 접근 권한이 필요합니다.")
                    .foregroundColor(.orange)
            } else {
                List {
                    ForEach(groupedCalendars.keys.sorted(), id: \.self) { source in
                        Section(header: Text(source)) {
                            ForEach(groupedCalendars[source] ?? [], id: \.calendarIdentifier) { calendar in
                                CalendarRow(calendar: calendar, settings: settings)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }
    
    private var groupedCalendars: [String: [EKCalendar]] {
        Dictionary(grouping: calendarService.availableCalendars) { calendar in
            calendar.source?.title ?? "기타"
        }
    }
}

struct CalendarRow: View {
    let calendar: EKCalendar
    @ObservedObject var settings: SettingsManager
    
    private var isIncluded: Bool {
        !settings.excludedCalendarIDs.contains(calendar.calendarIdentifier)
    }
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { isIncluded },
            set: { newValue in
                if newValue {
                    settings.excludedCalendarIDs.remove(calendar.calendarIdentifier)
                } else {
                    settings.excludedCalendarIDs.insert(calendar.calendarIdentifier)
                }
            }
        )) {
            HStack {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
                    .frame(width: 10, height: 10)
                
                Text(calendar.title)
            }
        }
    }
}

#Preview {
    SettingsView(calendarService: CalendarService(), settings: SettingsManager.shared)
}
