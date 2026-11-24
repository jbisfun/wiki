# clock-ios

[Fossify Clock](https://github.com/FossifyOrg/Clock) 以 SwiftUI 在 iOS 上重新打造，透過 AlarmKit（iOS 26 以上）或本機通知響鈴。

    idl build -c release     # -> build/release/FossifyClock.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyClock

已移植：時鐘分頁，含額外時區（新增、重新命名、刪除）與下一個鬧鐘；鬧鐘支援星期、音效（預設、無或您自己的音訊檔）、震動、標籤、貪睡、可略過下一次響鈴的「即將響起的鬧鐘」提示、排序與拖曳重新排列，以及可滑動關閉／貪睡的鬧鐘畫面；含可排序分圈的碼錶；任意數量的計時器，支援音效、震動、標籤、排序與重新排列；匯出／匯入鬧鐘與計時器（與 Android 相同的 JSON）；色彩與所有適用的設定；數位與類比時鐘主畫面小工具及其背景／文字色彩設定（位於 launcher-ios 內）。

因 iOS 而不得不有的差異：小工具僅能在 launcher-ios 內使用（iOS 主畫面小工具需要 WidgetKit 擴充功能）、沒有「啟動碼錶」啟動器捷徑，計時器與碼錶也沒有持續顯示的「執行中」通知；使用 AlarmKit 時由系統警示響鈴（貪睡採用貪睡時間；震動、漸強音量與最長提醒時間僅在應用程式開啟時適用）；未使用時，鬧鐘為時效性通知，最多播放 30 秒的聲音；無法列出系統鈴聲；沒有應用程式內語言切換。

GPL-3.0，與原版相同。
