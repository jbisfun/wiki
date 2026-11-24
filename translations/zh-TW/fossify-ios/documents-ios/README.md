# documents-ios

[Fossify Documents](https://github.com/FossifyOrg/Documents) 以 SwiftUI 在 iOS 上重新打造，建構於 PDFKit 與 WebKit 之上。

    idl build -c release     # -> build/release/FossifyDocuments.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyDocuments

已移植：首頁含最近使用、我的最愛與資料夾，「檢視全部」清單，含階層路徑的資料夾瀏覽、搜尋、類型篩選、排序、清單／格狀檢視、多選（加入我的最愛、分享、全選、以其他 App 開啟、移除）；開啟檔案／資料夾，以及新增文字／Markdown 檔案；PDF 閱讀器（垂直或水平翻頁、記住頁面、頁面指示器、目錄、尋找、前往頁面、縮放、深色頁面、密碼、儲存副本、列印）；文字與 Markdown 編輯器（含醒目標示的尋找、雙指／選單縮放、字數／字元統計、格式工具列、Markdown 預覽、編碼、唯讀提示、另存新檔／編輯副本、重新開啟以編輯）；DOCX 與 HTML 閱讀器，含尋找功能（已封鎖指令碼與遠端載入）；CSV 表格，可改以文字編輯；開啟來自其他 App 的文件；顏色與所有設定。

iOS 造成的差異：選取的檔案與資料夾透過安全範圍書籤（security-scoped bookmarks）記住，而非持久化的 URI 權限；DOCX 頁面由 WebKit/QuickLook 轉譯，而非 mammoth HTML 轉換；新檔案與副本透過系統的「移動至」選擇器放置；沒有 App 內語言切換或自訂閱讀器字型。

GPL-3.0，與原版相同。
