# MenuBarCalendar

macOS 메뉴바에서 현재 일정이나 다음 일정을 바로 확인할 수 있는 캘린더 앱이다.  
Apple Calendar 데이터를 읽어서 메뉴바에 핵심 정보만 가볍게 보여주고, 클릭하면 다가오는 일정 목록과 설정 화면을 열 수 있다.

## 주요 기능

- 메뉴바에 현재 진행 중인 일정 또는 다음 일정 표시
- 클릭 시 팝오버에서 다가오는 일정 목록 확인
- 일정 항목을 눌러 Apple Calendar에서 바로 열기
- 표시할 캘린더 선택
- 겹치는 일정 우선순위 설정
- 하루 종일 이벤트 표시 여부 설정
- 메뉴바 텍스트 길이, 조회 범위, 표시 개수 설정
- 인디케이터 스타일과 배경 색상 커스터마이징

## 사용 환경

- macOS
- Xcode
- SwiftUI
- EventKit

## 실행 방법

1. `MenuBarCalendar.xcodeproj`를 Xcode로 연다.
2. 실행 타깃을 `My Mac`으로 맞춘다.
3. 앱을 실행한다.
4. 처음 실행하면 캘린더 접근 권한을 허용한다.

권한이 없으면 메뉴바와 팝오버에서 일정을 불러올 수 없다.

## 앱 동작 방식

- 진행 중인 일정이 있으면 그 일정을 우선 표시한다.
- 진행 중인 일정이 없으면 가장 가까운 다음 일정을 표시한다.
- 메뉴바 텍스트는 설정한 최대 길이에 맞춰 축약된다.
- 일정 목록은 선택한 캘린더와 표시 옵션을 반영해서 갱신된다.

## 설정 가능 항목

- 제목 최대 길이
- 조회 범위
- 다가오는 일정 표시 개수
- 겹치는 일정 처리 방식
- 하루 종일 이벤트 표시 여부
- 인디케이터 스타일
- 인디케이터 색상 모드
- 배경 표시 여부
- 배경 색상 모드와 세부 조정값
- 캘린더별 표시/숨김

## 프로젝트 구조

- `MenuBarCalendar/MenuBarCalendarApp.swift`: 앱 시작점과 메뉴바 항목 구성
- `MenuBarCalendar/Services/CalendarService.swift`: 캘린더 권한, 이벤트 조회, 상태 갱신
- `MenuBarCalendar/Views/MenuContent.swift`: 팝오버 UI
- `MenuBarCalendar/Views/SettingsView.swift`: 설정 화면
- `MenuBarCalendar/Models/Settings.swift`: 사용자 설정 저장

## 참고

이 프로젝트는 Apple Calendar 데이터를 기반으로 동작하므로, 로컬 캘린더 상태와 권한 설정에 따라 표시 결과가 달라질 수 있다.
