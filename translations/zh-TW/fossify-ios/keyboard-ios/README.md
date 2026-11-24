# keyboard-ios

[Fossify Keyboard](https://github.com/FossifyOrg/Keyboard) 以 SwiftUI 與 UIKit 在 iOS 上重新打造。

    idl build -c release     # -> build/release/FossifyKeyboard.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyKeyboard

IPA 包含 App 與 `KeyboardExtension.appex`（系統鍵盤；設定 > 一般 > 鍵盤 > 鍵盤 > 加入新鍵盤 > Fossify Keyboard，然後允許完整取用權限）。兩者共用 `KeyboardKit`，其 `KeyboardInputView` 同時也是 App 本身文字欄位的 `inputView`，因此不需啟用即可在 App（以及啟動器）內使用該鍵盤。

已移植：上游的所有版面配置與語言（50 種按鍵版面配置讀取自上游 XML，含數字、電話與三頁符號頁面）、Shift／點兩下鎖定大寫與句首大寫、含重音符號的長按彈出視窗與工具彈出視窗、按鍵預覽彈出視窗、連續刪除、空白鍵游標控制、長按空白鍵切換語言、表情符號／語言切換鍵、越南語 Telex、含分類與最近使用表情符號的表情符號面板、顯示目前剪貼內容的工具列、含目前與釘選剪貼內容的剪貼簿管理員、管理剪貼簿項目（新增、編輯、刪除、重新排序、匯入／匯出 JSON），以及所有設定：顏色、鍵盤語言、管理鍵盤語言、按鍵邊框、數字列、表情符號／語言切換鍵、鍵盤高度、按鍵時彈出、震動、按鍵音效（關閉／跟隨系統／永遠開啟）、句首大寫、顯示剪貼簿內容。

iOS 造成的差異：全系統使用需要具備完整取用權限的鍵盤擴充功能（剪貼簿、音效、觸覺回饋，設定透過 App Group 共用）；擴充功能的設定與剪貼簿按鈕會開啟 App；沒有語音輸入法或自動填寫建議；當 iOS 要求時會出現「下一個鍵盤」地球按鈕；頂列的預覽顯示在按鍵旁邊（鍵盤無法在自身上方繪製）；「變更鍵盤」會開啟設定；沒有 App 內語言切換；圖示為 SF Symbols。

GPL-3.0，與原版相同。
