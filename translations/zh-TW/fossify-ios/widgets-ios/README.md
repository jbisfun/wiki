# widgets-ios

Fossify App 的主畫面小工具，以 WidgetKit
擴充功能（SwiftUI、App Intents）在真正的 iOS 主畫面上重新打造。launcher-ios 內嵌了它；此儲存庫也會建置一個小型主機 App。

    idl build -c release     # -> build/release/FossifyWidgets.ipa with PlugIns/WidgetsExtension.appex

需要 PATH 中有 `appintentsmetadataprocessor`（[re-appintentsmetadataprocessor](https://codeberg.org/viraptor/re-appintentsmetadataprocessor)，
例如 `nix profile install nixpkgs#re-appintentsmetadataprocessor`）：idl 會寫入 `Metadata.appintents`，
沒有它的話，iOS 會忽略小工具的設定與按鈕。

## 小工具

| 小工具 | 尺寸 | 設定（編輯小工具） | 互動 |
| --- | --- | --- | --- |
| 計算機 | 大、特大 | 背景顏色 + 不透明度、文字顏色 | 每個按鍵（狀態存於 App Group） |
| 日期（行事曆） | 小 | 顏色 | |
| 事件清單（行事曆） | 小 - 特大 | 期間／自訂天數、標頭、顏色 | |
| 月檢視（行事曆） | 小、大、特大 | 顏色 | 上個月／今天／下個月 |
| 數位時鐘 | 小、中 | 顏色 | |
| 類比時鐘 | 小、中 | 背景 | |
| 圖庫資料夾 | 小 - 大 | 資料夾、資料夾名稱、顏色 | |
| Music Player | 中 | 顏色 | 上一首／播放暫停／下一首（在 App 行程中） |
| 筆記 | 小 - 特大 | 筆記、標題、顏色 | |
| 錄音（Voice Recorder） | 小 | 顏色 + 不透明度 | 開始（開啟 App）／停止並儲存 |

顏色為 Material 色票加上「主題」（各 App 的主色）或自訂的 `#RRGGBB`。點按其他位置會在啟動器中
開啟 `fossify://open/<app>?...`（筆記 ID、資料夾路徑）。

## 新增小工具

長按主畫面，編輯 > 加入小工具，搜尋「Fossify Widgets」，然後選擇一個。長按已
放置的小工具 > 編輯小工具，即可進行其設定。

## 運作方式

- `Extension/`：`@main WidgetBundle`，每個 Android AppWidgetProvider 對應一個小工具，依據快照繪製，外觀與
  啟動器內的移植版（`*-ios/Sources/UI/Widgets.swift`）相同。
- 各 App 會從每個 Kit 中的 `<App>WidgetData.install()`（`Sources/Model/HomeScreenWidget.swift`）將快照發佈到啟動器的 App Group（`FossifyCommons.WidgetBridge`、
  `WidgetSnapshots.swift`），並在資料變更時重新載入時間軸。圖庫封面與音樂封面圖片以 JPEG 檔案寫入。
- `Shared/`：必須在 App 中執行的 intent（音樂控制項為 `AudioPlaybackIntent`，以及錄音）；App
  也會連結此模組，使它們包含在其 `Metadata.appintents` 中。
- 重新簽署會重新命名 App Group（`group.org.fossify.launcher.ios` 會透過
  Jimpactor 變成 `...ios.<TEAMID>`）；`FossifyCommons.AppGroup` 會在執行階段找到具備權利的那一個。

iOS 造成的差異：小工具顯示 App 最後發佈的資料（它們會在 App 執行時更新，而非
即時；若小工具看起來過時，請開啟 App）；時間軸依 WidgetKit 的額度重新整理（時鐘與事件清單使用
預先計算的每分鐘／每 15 分鐘項目，當 App 的 24 小時制
設定與系統相符時，數位時鐘則使用即時的 `Text(.time)`）；沒有捲動清單（過長的筆記與事件清單會被截斷）；小工具背景為
iOS 容器（其圓角半徑、對主畫面的透明度）；開始錄音會開啟 Voice
Recorder（麥克風無法在背景啟動）；受保護的筆記不顯示內容（小工具中沒有密碼提示）；計算機在每次按鍵往返（intent）後才顯示結果，且其歷史記錄會在啟動器下次執行時併入
App 的歷史記錄；所有月檢視小工具共用同一個月份偏移量
（與上游相同），並維持在已發佈的往前 2 個月至往後 12 個月範圍內。
