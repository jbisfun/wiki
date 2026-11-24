# phone-ios

[Fossify Phone](https://github.com/FossifyOrg/Phone) 以 SwiftUI 在 iOS 上重新打造，建立於系統聯絡人儲存區（`Contacts.framework`）之上；通話透過 `tel:` URL 撥出。

    idl build -c release     # -> build/release/FossifyPhone.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyPhone

已移植：聯絡人／我的最愛／通話記錄分頁，含搜尋、字母快速捲動列、多選操作、排序與來源篩選；可自訂順序並提供格狀檢視的我的最愛；撥號鍵盤，含 T9 聯絡人搜尋、快速撥號、DTMF 嗶聲與震動；通話確認與號碼選擇器；依日期與連續通話分組的通話記錄、通話詳細資料、封鎖／刪除／複製／簡訊操作、JSON 匯出／匯入；封鎖號碼；色彩、字型大小、日期／時間格式，以及所有適用的設定。

因 iOS 而不得不有的差異：無法存取通話記錄，因此通話記錄僅包含從本應用程式發起的通話（通話時間透過 CallKit 的觀察者取得）以及匯入的通話；沒有撥號程式角色，因此沒有通話中畫面、來電處理、來電過濾、SIM 卡選擇、號碼歸屬地或密技碼（及其設定）；封鎖號碼僅會在應用程式中隱藏通話，並阻止從應用程式撥出；我的最愛由應用程式自行儲存；聯絡人在系統聯絡人畫面中檢視與建立；沒有啟動器捷徑。

GPL-3.0，與原版相同。
