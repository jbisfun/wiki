# calendar-ios

[Fossify Calendar](https://github.com/FossifyOrg/Calendar) 以 SwiftUI 在 iOS 上重新打造，透過 `EventKit` 使用系統行事曆。

    idl build -c release     # -> build/release/FossifyCalendar.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyCalendar

已移植：日、週（可調整天數）、月、月＋日、年與事件清單檢視，支援滑動、前往今天／指定日期、搜尋與快速行事曆篩選；事件與工作支援全天、時區、三個提醒、所有重複規則（包括第 N 個／最後一個星期幾、限制與個別發生項目的編輯）、狀態、忙閒狀態、色彩、複製／分享／刪除；本機行事曆（管理、色彩）與同步行事曆（「CalDAV 同步」= iOS 設定中的帳號，即時讀取與寫入）；工作完成；所有上游國家的假日、聯絡人生日與紀念日；.ics 匯入／匯出／分享；含貪睡與標示為已完成的提醒通知；自動備份（檔案 › 在我的 iPhone 上 › Calendar › Backups）；設定匯出／匯入；色彩、字型大小與所有適用的設定；日期、事件清單與月曆主畫面小工具及其設定畫面（色彩、清單期間與標頭）。

因 iOS 而不得不有的差異：主畫面小工具可在 launcher-ios 內使用（iOS 主畫面小工具需要 WidgetKit 擴充功能），點一下會開啟應用程式的主畫面；同步行事曆的提醒來自該行事曆自己的警示，且只會排程接下來的 64 個應用程式提醒（每次開啟應用程式時重新整理）；提醒音效、音訊串流、震動與循環播放遵循系統通知設定；自動備份改為在上午 6 點後開啟應用程式時執行，而非由鬧鐘觸發；沒有應用程式內語言切換或啟動器捷徑。

GPL-3.0，與原版相同。
