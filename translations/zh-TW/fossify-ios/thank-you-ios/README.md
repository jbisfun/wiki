# thank-you-ios

[Fossify Thank You](https://github.com/FossifyOrg/Thank-You) 以 SwiftUI 在 iOS 上重新打造。

    idl build -c release     # -> build/release/FossifyThankYou.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyThankYou

已移植：捐款通知（F-Droid 版本）與捐款畫面（平台與加密貨幣位址，可開啟或複製）、已安裝的 Fossify App 清單，含版本、套件、簽署者與安裝來源（點按即可開啟，自身則顯示「Hello :)」）；設定：顏色，以及與啟動器中每個 App 共用的全域「所有 Fossify App」選項、在開關上顯示勾號，以及儲存空間單位（十進位／二進位）；關於。

iOS 造成的差異：App 無法列舉或檢查其他已安裝的 App，因此清單只會單獨顯示本 App，並在啟動器內顯示隨附的 App，且不存在「可能不安全的 App」（簽章不符）與解除安裝功能；簽署者與安裝來源來自佈建描述檔；沒有 App 內語言切換，也沒有替代的啟動器圖示。

GPL-3.0，與原版相同。
