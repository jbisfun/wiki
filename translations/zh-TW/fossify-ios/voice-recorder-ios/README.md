# voice-recorder-ios

[Fossify Voice Recorder](https://github.com/FossifyOrg/Voice-Recorder) 以 SwiftUI 在 iOS 上重新打造，建構於 `AVFoundation`（`AVAudioRecorder` / `AVAudioPlayer`）之上。

    idl build -c release     # -> build/release/FossifyVoiceRecorder.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyVoiceRecorder

已移植：錄音器具備即時振幅視覺化、暫停／繼續（暫停時閃爍）、儲存與捨棄；錄音可在背景持續進行；播放器具備播放／暫停、上一首／下一首、拖曳進度列、時間標籤上的 ±10 秒跳轉、長按標題以複製、拔除耳機時暫停；搜尋；多選重新命名、分享、以其他 App 開啟、刪除（移至資源回收桶或略過）、全選；資源回收桶分頁，可還原／刪除，並於 30 天後到期；顏色、日期與時間格式、啟動後開始錄音、保持螢幕開啟、儲存資料夾（檔案中的任何資料夾，並可選擇移動既有錄音）、檔名格式、副檔名、位元率、取樣率、麥克風模式與資源回收桶設定；launcher-ios 內的 1x1 錄音小工具（白色麥克風，錄音時會上色，點按即可開始或停止並在背景儲存；背景顏色與透明度）。錄音預設存放於檔案 › 在我的 iPhone 上 › Voice Recorder › Recordings。

iOS 造成的差異：不支援 mp3（iOS 沒有編碼器），且 Opus 以 .caf 而非 .ogg 寫入；麥克風模式為 iOS 所提供的 AVAudioSession 模式（沒有語音效能／辨識）；主畫面小工具僅能在 launcher-ios 內使用（iOS 主畫面小工具需要 WidgetKit 擴充功能）；沒有錄音通知（iOS 會顯示自己的麥克風指示器）、供其他 App 使用的「錄製聲音」intent，也沒有 App 內語言切換。

GPL-3.0，與原版相同。
