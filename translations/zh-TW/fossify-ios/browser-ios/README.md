# browser-ios

[AOSP Browser](https://android.googlesource.com/platform/packages/apps/Browser/+/refs/tags/android-6.0.1_r81)（最後一個完整版本，Android 6.0.1）以 SwiftUI 在 iOS 上，基於 WKWebView 並以 Fossify 風格重新打造。

    idl build -c release     # -> build/release/FossifyBrowser.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyBrowser

已移植：手機介面（含安全性／網站圖示的標題列、網址輸入、停止／重新載入、分頁數量、選項選單；頁面進度列）；網址建議（輸入的文字、書籤、記錄、搜尋引擎的建議、「插入」箭頭）；分頁與 NavScreen 分頁切換器（含標題、關閉與頁面縮圖的卡片、滑動關閉、新增分頁、關閉其他分頁）、16 個分頁上限、在新分頁中開啟彈出視窗／`target=_blank`、`window.close()`；無痕分頁（共用的非持久性資料儲存區，隨最後一個無痕分頁一併捨棄，絕不儲存）；含資料夾與階層路徑的書籤、新增／編輯／移動／刪除、資料夾「全部開啟」、書籤／記錄的內容選單、設為首頁；依日期分組的記錄（今天、昨天、最近 7 天、上個月、更早）加上最常瀏覽、星號切換、清除；含縮圖的最常瀏覽首頁；含符合數量的頁面內尋找；分享頁面；儲存以供離線閱讀（已儲存的頁面，`.webarchive`）；下載（WKDownload、儲存連結、儲存圖片）至 Documents/Download，並提供下載清單；每個分頁可要求桌面版網站；含憑證的頁面資訊；連結（開啟、在新／背景分頁中開啟、儲存連結、拷貝、分享）、圖片（儲存、檢視、拷貝網址、分享）、`tel:` 與 `mailto:` 的長按選單；JavaScript alert/confirm/prompt、HTTP 驗證、SSL 警告對話框；位置（每個網站各自提示，含「記住偏好設定」）、相機與麥克風提示；分頁（含上一頁／下一頁清單）、書籤、記錄、網站圖示與縮圖以 JSON/JPEG 持久保存；`BrowserRoot(openURL:)` 可開啟頁面或本機的 `.html`/`.webarchive`。設定：首頁（目前頁面、空白、預設、最常瀏覽、其他）、隱私權與安全性（清除快取／記錄／Cookie／所有網站資料、安全性警告、接受 Cookie、啟用位置、清除位置存取權）、輔助使用（強制啟用縮放、文字縮放、最小字型大小、反相轉譯 + 對比，含預覽）、進階（搜尋引擎、搜尋建議、在背景開啟、JavaScript、網站設定、封鎖彈出視窗、桌面版網站、重設為預設值）、頻寬（載入圖片）。

iOS 造成的差異：頁面由 WebKit 繪製，而非 Chromium（見下文）；表單自動填寫與已儲存的密碼屬於 iOS 的「自動填寫」，因此相關設定已移除；外掛程式、文字編碼、預設縮放、概覽模式、預先載入、快速控制項與主畫面捷徑在 WKWebView／iOS 上沒有對應功能；由於 WKWebView 沒有公開的各網站位置回呼，地理位置透過注入的 `navigator.geolocation` shim 處理；文字縮放、強制縮放與反相轉譯為注入的 CSS，圖片與 Cookie 封鎖則是內容規則清單；搜尋引擎清單為現今的搜尋引擎；本 App 無法成為系統預設瀏覽器。

## Chromium

所有瀏覽器程式碼都與 `BrowserEngine`/`BrowserPage`（Sources/Engine/BrowserEngine.swift）溝通；`WebKitEngine` 是唯一的實作，並在 `Engines.current` 中選取。Blink 引擎將會是這兩個協定的第二種實作。發現（未嘗試建置）：

- BrowserEngineKit（iOS 17.4+）是執行非 WebKit 引擎的唯一方式：主機 App 需要 `com.apple.developer.web-browser-engine.host`，加上三個具備 `.webcontent`（JIT 為選用）、`.networking` 與 `.rendering` 的 arm64e 擴充功能行程，以及預設瀏覽器權利（或用於 App 內瀏覽的嵌入式引擎權利）。Apple 依 App 逐一應請求授予，僅限於歐盟（iOS 17.4+）與日本（iOS 26.2+）發佈；開發版本僅能在這些地區的裝置上執行。
- 此處的 darwin SDK（`~/.swiftpm/swift-sdks/darwin.artifactbundle`，iPhoneOS 27.2）隨附 BrowserEngineKit 與 BrowserEngineCore（標頭檔、`.tbd`、swiftinterface：`BEWebContentProcess`、`BENetworkingProcess`、`BERenderingProcess`、`BELayerHierarchy`、`BEScrollView`、`BETextInput`，……），且 idl 會建置 `appex` 目標，因此主機／擴充功能骨架可在 Linux 上編譯。
- Chromium 的 iOS Blink 移植為 GN `use_blink = true`（目標 `content_shell`、`chrome`），上游標示為「實驗性，僅供分析」。建置需要安裝 Xcode 26+ 與 iOS 模擬器執行環境的 Mac（`ios/build/tools/setup-gn.py`）；無法在 Linux 上建置。
- Jimpactor 側載使用免費／付費的開發憑證簽署，其描述檔無法攜帶 web-browser-engine 權利（受管理，僅授予經核准的 App ID），而且 iOS 會拒絕啟動宣告了其描述檔所缺少之受限權利的二進位檔。Blink 在 iOS 上也無法於單一一般 App 行程內執行（沒有 JIT、沒有子行程），因此沒有免權利的替代方案。
- 結論：取代 WKWebView 需要 Apple 核准的歐盟／日本瀏覽器權利描述檔以及 macOS 上的 Chromium 建置；在此之前，WebKit 是本 App 唯一能夠發佈的引擎。

GPL-3.0，與其他 Fossify 移植版相同；其所依循的 AOSP Browser 為 Apache-2.0。
