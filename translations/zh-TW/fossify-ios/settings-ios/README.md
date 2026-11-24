# settings-ios

[AOSP Settings](https://android.googlesource.com/platform/packages/apps/Settings) 以 SwiftUI 在 iOS 上以 Fossify 風格（FossifyCommons）分支而成，供 [launcher-ios](https://github.com/jbisfun/launcher-ios) 中隨附的 Fossify App 使用。

    idl build -c release     # -> build/release/FossifySettings.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifySettings

已移植：首頁（搜尋列、彩色分類圖示、AOSP 標題與摘要）以及跨所有設定的搜尋；僅保留 Settings 能夠變更的設定。**App**：所有 App、App 資訊（開啟、清除快取、通知、含清除儲存空間的儲存空間與快取、App 內的其他設定），以及啟動器的 App 項目（預設／隱藏的 App）。**通知**：各 App 的開關（由 commons 的 `NotificationHub` 遵循）以及 iOS 通知權限。**儲存空間**：已用／可用、釋放空間（每個 App 的快取）、依 App、類型（圖片、影片、音訊、文件）與資料夾的使用量、二進位單位。**顯示**：亮度等級、螢幕逾時（保持螢幕開啟）、深色主題、顏色、顯示大小與文字（Fossify 字型大小）、自動旋轉，以及啟動器的顯示／桌布項目。**輔助使用**：顯示大小與文字、顏色、開關上的勾號。**安全性與隱私**：共用的 App 鎖定（圖形／PIN／生物辨識）與鎖定時機、刪除保護。**系統**：啟動器項目（手勢／導覽，……）、日期與時間（24 小時制、日期格式）、備份（匯出／匯入每個 App 的設定）、重設選項（重設 App 偏好設定、清除所有資料）。透過 commons 的 `SystemSettingsRegistry` 註冊的設定會顯示於其分類與搜尋中。

iOS 造成的差異：獨立的 App 只能看到自己的行程，因此 App 與啟動器項目僅會出現在 launcher-ios 內；網路、藍牙、電池、聲音、位置、帳號、語言與關於因 iOS 不允許 App 變更而被省略；螢幕逾時只能設為「永不」，各 App 的資料依各移植版已知的檔案與鍵值找到（`scripts/gen_app_keys.py`），而清除資料或匯入設定需在 Fossify 重新啟動後才會完全生效。

Apache-2.0（AOSP Settings）／ GPL-3.0（Fossify）。
