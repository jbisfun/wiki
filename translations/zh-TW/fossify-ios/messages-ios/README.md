# messages-ios

[Fossify Messages](https://github.com/FossifyOrg/Messages) 以 SwiftUI 在 iOS 上重新打造，透過系統編輯器（`MessageUI`）傳送，收件者來自系統聯絡人儲存區（`Contacts.framework`）。

    idl build -c release     # -> build/release/FossifyMessages.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyMessages

已移植：對話支援搜尋（標題與訊息文字）、釘選、已讀／未讀、重新命名、詳細資料，以及封存與資源回收筒及其所有操作；訊息串含日期標頭、已傳送／失敗狀態、重試、多選複製／分享／儲存／轉寄／選取文字／內容，以及超連結文字與影像／影片／音訊／vCard／檔案附件；新增成員、含建議與字母索引的新對話；附件選擇器（照片、影片、相機、音訊、檔案、聯絡人），含 MMS 影像縮放；排程訊息；草稿；封鎖號碼與關鍵字，可匯入／匯出；Fossify JSON（以及 SMS Backup & Restore XML）訊息匯入／匯出；日期格式、色彩、字型大小、密碼保護，以及所有適用的設定。

因 iOS 而不得不有的差異：沒有簡訊資料庫，也沒有預設簡訊應用程式角色，因此對話僅包含從備份匯入的，加上從應用程式傳送的訊息；收到的簡訊永遠不會抵達，抵達時也不會封鎖任何內容或發出通知；每則訊息都要在系統編輯器中確認（會遵循群組 MMS 或個別訊息的選擇，無法選擇 SIM 卡與傳送回報）；排程訊息會在到期時發出通知並開啟編輯器，而非在背景傳送；沒有各對話的通知頻道、啟動器捷徑與「使用英文」。

GPL-3.0，與原版相同。
