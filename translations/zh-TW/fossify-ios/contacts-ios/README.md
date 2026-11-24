# contacts-ios

[Fossify Contacts](https://github.com/FossifyOrg/Contacts) 以 SwiftUI 在 iOS 上重新打造，建立於系統聯絡人儲存區（`Contacts.framework`）之上。

    idl build -c release     # -> build/release/FossifyContacts.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyContacts

已移植：聯絡人／我的最愛／群組分頁，含搜尋、字母快速捲動列、多選操作、排序與來源篩選；檢視／編輯聯絡人，支援所有 Fossify 欄位與標籤；群組；可自訂順序並提供格狀檢視的我的最愛；撥號鍵盤；vCard 匯入／匯出／分享；自動備份（檔案 › 在我的 iPhone 上 › Contacts › Backups）；色彩、字型大小，以及所有適用的設定。

因 iOS 而不得不有的差異：我的最愛與預設號碼由應用程式自行儲存（iOS 的資料為其私有）；不顯示備註與鈴聲（受限的權限／沒有 API）；自動備份改為在上午 6 點後開啟應用程式時執行，而非由鬧鐘觸發；沒有啟動器捷徑、私人聯絡人與「開啟方式」。

GPL-3.0，與原版相同。
