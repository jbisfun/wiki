# paint-ios

[Fossify Paint](https://github.com/FossifyOrg/Paint) 以 SwiftUI 在 iOS 上重新打造，使用 Core Graphics 繪圖。

    idl build -c release     # -> build/release/FossifyPaint.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyPaint

已移植：畫布，含平滑筆觸、點、橡皮擦、滴管與向量油漆桶填色（相連的同色區域，也適用於已開啟的影像）、最多 1000 步的復原／重做（包括復原清除）、雙指縮放與移動、筆刷色彩選擇器與筆刷大小工具；儲存為 PNG、SVG 或 JPG 並記住上次使用的格式、分享、列印、從「照片」或「檔案」以及透過「在其他 App 中開啟」開啟影像與 SVG（也包括 Fossify Paint 自己的 SVG）、變更背景色彩、未儲存變更提示；色彩與所有設定（保持螢幕開啟、筆刷大小工具、縮放、相對縮放的筆刷大小、強制直向）。

因 iOS 而不得不有的差異：由系統儲存面板選擇資料夾，沒有供其他應用程式使用的「拍照」／「編輯」模式（沒有 IMAGE_CAPTURE/EDIT 意圖），色彩選擇器為系統內建的，沒有應用程式內語言切換，且工具圖示為 SF Symbols。

GPL-3.0，與原版相同。
