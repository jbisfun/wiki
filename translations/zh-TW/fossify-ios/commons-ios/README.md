# commons-ios

Fossify iOS 移植版的共用核心（[contacts-ios](https://github.com/jbisfun/contacts-ios)、[calculator-ios](https://github.com/jbisfun/calculator-ios)），對應 [Fossify Commons](https://github.com/FossifyOrg/Commons)。Swift 模組 `FossifyCommons`。

- `BaseConfig`：佈景主題、自訂色彩、字型大小（每個應用程式使用相同的 UserDefaults 鍵）
- `Theme`：`ThemeKind`、`Palette`（`\.palette` 環境值）、用於應用程式根視圖的 `.fossifyTheme()`、`.paletteBackground()`
- `Components`：`RadioDialog`、`CheckRow`、`DialogFrame`、`DialogButtons`、`.toast`、`.sectionHeader`、`TopBar`、`IconButton`、`PressedStyle`、`Launcher`，以及隱藏導覽列時的滑動返回
- `Settings`：`SettingsItem`、`SettingsToggle`、`CustomizeColorsView`、`AboutView(app: AppInfo)`
- `Hosting`：供在 [launcher-ios](https://github.com/jbisfun/launcher-ios) 內執行的應用程式使用的 `\.closeApp`／`CloseAppButton`
- `NotificationHub`：行程唯一的通知委派與合併後的類別集合；應用程式改為註冊處理常式，而不是設定通知中心的委派
- `DateTimeFormat`：日期格式／24 小時制設定，含 `format(_:)`、`ChangeDateTimeFormatDialog`、`Int.formattedDuration()`、`Int64.formattedSize`
- `ColorPickerDialog`：以工作表呈現的系統色彩選擇器；用於「強制直向模式」的 `OrientationLock` + `OrientationLockDelegate`
- `SecurityDialog`：圖形密碼／PIN／Face ID 分頁、`SecurityConfig`、`.securityCheck($request)`、`.appLock()`、`PasswordProtectionToggle`（需要 `NSFaceIDUsageDescription`）
- `StoredProtection`：隱藏項目／各資料夾（`ProtectionKeys.hiddenItems`、`.folder(path)`）或應用程式專屬的保護、`StoredProtection.check(_:onSuccess:)`、`StoredProtectionToggle`
- `AutoBackup`：上午 6 點的備份時段、`%Y%M%D_%h%m%s` 檔名、`currentFormattedDateTime()`、`DateTimePatternInfoDialog`
- 檔案：`FileDirItem` + `Sorting`/`ViewTypes`、`StorageRoot`、`Breadcrumbs`、`FilePickerDialog`、`StoragePickerDialog`、`CreateNewFolderDialog`、`DialogTextField`、`PropertiesDialog`、`RenameItemDialog` / `RenameItemsDialog`、`FileConflictDialog` + `.conflictCheck($check)`
- 鬧鐘：`WeekDays`（每週第一天、星期位元／名稱）、`DurationStrings`、`PickSecondsDialog` / `CustomIntervalPickerDialog`、`AlarmSound` / `SelectAlarmSoundDialog` / `AlarmSoundPlayer`、`ReminderConfig`（貪睡、鬧鐘警告、您的音效）
- `ShareSheet`：`ShareSheet` / `ShareItems`（系統分享工作表）、`Launcher.openWith(_:)`（「開啟方式」選擇器）、`Launcher.topViewController()`
- 清單：`ActionModeBar`（選取 CAB）、`OverflowMenu`、`toggleSelection(_:in:)`、`FastScroller`（RecyclerViewFastScroller 的把手＋氣泡）
- `BlockedNumbers`：共用的封鎖清單，含 `isBlocked(_:)`（也支援比對樣式）、`ManageBlockedNumbersView`、`BlockedItemsView`（新增／編輯、複製、刪除、.txt 匯入／匯出）、`ExportTextFileDialog`
- `GlobalSettings`：全域的「在開關上顯示勾號」／「二進位儲存單位」鍵、`CheckmarkSwitchStyle`（供 `SettingsToggle` 使用）；`DonationView`（DonationActivity：平台＋加密貨幣位址）
- `LetterFastScroller`（indicatorfastscroll 字母欄＋氣泡、`firstIDs`）、`KeypadHelper`（T9 字母 -> 數字、按鍵字母）、`DateTimeFormat.formatDateOrTime(...)`、`DurationStrings.shortTime(_:)`（「1h 5m 3s」）
- `OpenDeviceSettingsDialog(message:)`（權限遭拒 -> 「前往設定」）、`Launcher.openDeviceSettings()`
- `ColorShading`：`UInt32.darkened(by:)` / `lightened(by:)` / `alphaAdjusted(_:)` / `contrastARGB`（Commons 的 darkenColor / lightenColor / adjustAlpha / getContrastColor）

應用程式會在 pull 工作區中將它簽出到自己旁邊（`fossify-ios/commons-ios`），並以 idl 靜態目標建置：

```yaml
targets:
  - name: FossifyCalculator
    link: [FossifyCommons]
    # ...
  - name: FossifyCommons
    type: static
    dir: ../commons-ios
    min_ios: "17.0"
    sources: [Sources]
    frameworks: [SwiftUI, UIKit, Foundation]
    swift_version: "5.0"
```

GPL-3.0，與 Fossify Commons 相同。
