# music-player-ios

[Fossify Music Player](https://github.com/FossifyOrg/Music-Player) 以 SwiftUI 在 iOS 上重新打造，建構於 AVFoundation（`AVAudioEngine`）與 MediaPlayer 之上。

    idl build -c release     # -> build/release/FossifyMusicPlayer.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyMusicPlayer

已移植：播放清單、資料夾、演出者、專輯、曲目與類型分頁，具備搜尋、排序（播放清單與資料夾亦可個別排序）、快速捲動列與多選操作（加入播放清單／佇列、下一首播放、分享、內容、重新命名歌曲、刪除、排除資料夾）；「所有曲目」播放清單、建立播放清單（也可從資料夾或佇列建立）、將檔案／資料夾加入播放清單、拖放排序、M3U 匯入／匯出；播放器具備拖曳進度、點按跳轉 10 秒、隨機播放、重複播放（關閉／全部／單曲／目前歌曲結束後停止）、播放速度、下一首曲目與佇列；支援背景播放與鎖定畫面控制項、含預設組合的 5 頻段等化器、睡眠計時器、還原佇列與播放位置、播放從其他 App 開啟的音訊檔案；顏色、顯示的分頁、排除的資料夾、對調上一首／下一首耳機按鈕，以及以檔名作為標題；主畫面播放器小工具（歌曲資訊與上一首／播放暫停／下一首，可縮小為僅顯示控制列，並可設定背景顏色、透明度與文字顏色）。

iOS 造成的差異：歌曲來自 App 的資料夾（檔案 › 在我的 iPhone 上 › Music Player）以及音樂資料庫中非 DRM 的歌曲，App 無法刪除、重新命名或分享這些歌曲；編輯後的標籤由 App 自行儲存，而不是寫入檔案；等化器使用 Android 的標準頻段與預設組合，而非裝置本身的；鎖定畫面與控制中心的控制項取代通知；主畫面小工具僅能在 launcher-ios 內使用（iOS 主畫面小工具需要 WidgetKit 擴充功能），且沒有 App 內語言切換。

GPL-3.0，與原版相同。
