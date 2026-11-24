# file-manager-ios

[Fossify File Manager](https://github.com/FossifyOrg/File-Manager) 以 SwiftUI 在 iOS 上重新打造，可瀏覽應用程式自己的資料夾（「內部」，也會顯示在「檔案」App 中），以及從其他位置新增的任何資料夾（iCloud Drive、在我的 iPhone 上、USB 磁碟機、檔案提供者）。

    idl build -c release     # -> build/release/FossifyFileManager.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyFileManager

已移植：檔案／最近使用／儲存空間分頁，含階層路徑列、儲存空間選擇器、主資料夾、我的最愛、遞迴搜尋、各資料夾的清單／格狀檢視（含欄數與雙指縮放）、各資料夾的排序、隱藏項目；多選操作（刪除、含雜湊值的內容、重新命名／批次重新命名、分享、隱藏／取消隱藏、複製路徑、開啟方式、以其他方式開啟、含衝突處理的複製／移動、壓縮／解壓縮 zip）；建立檔案／資料夾；依類型的儲存空間分析，含各類型的檔案清單；文字編輯器，支援搜尋、儲存、另存新檔、列印與雙指縮放；zip 瀏覽器；儲存分享給本應用程式的檔案；色彩、字型大小、日期格式、密碼保護，以及所有適用的設定。

因 iOS 而不得不有的差異：應用程式只能存取自己的資料夾與使用者新增的資料夾，因此沒有全裝置儲存空間、SD 卡／OTG 或 root 存取，最近使用項目與儲存空間分析僅掃描這些資料夾；檔案以 QuickLook 開啟（文字在編輯器中、zip 在 zip 瀏覽器中），而非使用其他應用程式的意圖；沒有啟動器捷徑、「設為」桌布／鈴聲、檔案選擇器／鈴聲選擇器角色、「按兩次返回以離開」或應用程式內語言切換；檔案類型圖示為 SF Symbols；不支援有密碼保護的 zip（所使用的 zip 程式庫 ZIPFoundation 不支援加密）。

Zip 使用 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9（MIT），內含於 `Sources/Vendor/ZIPFoundation`。

GPL-3.0，與原版相同。
