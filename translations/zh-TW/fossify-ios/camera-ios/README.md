# camera-ios

[Fossify Camera](https://github.com/FossifyOrg/Camera) 以 SwiftUI 在 iOS 上重新打造。

    idl build -c release     # -> build/release/FossifyCamera.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyCamera

已移植：AVFoundation 相片與影片拍攝，含全螢幕直向預覽、影片／相片分頁（點選或滑動）、前後鏡頭切換、閃光燈模式關閉／自動／開啟／常亮（手電筒；影片中為開／關）、3／5／10 秒自拍計時器，含上游的倒數嗶聲與取消功能、解析度（全螢幕、16:9、4:3、1:1 相片裁切；UHD／FHD／HD／SD 影片）並依鏡頭與模式分別記憶、雙指縮放、點一下對焦與測光、快門閃光、旋轉圖示、錄影時間、可開啟預覽的最近拍攝縮圖；設定項目包括色彩、快門聲、音量鍵作為快門、最大亮度、exif 中繼資料、位置、翻轉前置相片、儲存位置（照片圖庫、相簿或「檔案」中的資料夾）、JPEG 品質與拍攝模式。

因 iOS 而不得不有的差異：相片快門聲僅能在 iOS 18 以上靜音（法律要求之處則一律無法靜音）；音量鍵作為快門需要 iOS 17.2，且也會接收相機控制按鈕；SD 影片為 640x480；沒有供其他應用程式使用的拍攝意圖、鎖定畫面使用或應用程式內語言切換；圖示為 SF Symbols。

GPL-3.0，與原版相同。
